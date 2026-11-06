<?php

namespace App\Services;

use App\Models\AccAccount;
use App\Models\AccAuditLog;
use App\Models\AccCardCategory;
use App\Models\AccCardImport;
use App\Models\AccDamaged;
use App\Models\AccPurchase;
use App\Models\AccReturn;
use App\Models\AccStock;
use App\Models\AccStockMovement;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-02 — the inventory document cycle (PLAN §2.1 + §3).
 *
 * Every stock-affecting document is ONE atomic transaction:
 *   the register row (purchase/damaged/return)
 *   + a signed acc_stock_movements row (never deleted)
 *   + the locked acc_stock balance (qty + weighted avg_cost)
 *   + a balanced journal entry via AccPostingService
 *   + acc_audit_log
 *
 * syncRouterCards() is the "كروت الراوتر تدخل تلقائياً" requirement:
 * it reconciles `cards` rows with source='mikrotik' into stock —
 * READ-ONLY on cards/card_categories/networks (isolation §0.3),
 * idempotent via the (ref_type=card, ref_id=card.id, type) unique
 * index. It runs lazily on every stock read and on POST /stock/sync.
 */
class AccStockService
{
    public function __construct(private AccPostingService $posting) {}

    // ── Primitive: one signed movement + locked balance ─────────

    /**
     * Append a movement and apply it to acc_stock atomically.
     * $qty is signed (positive=in, negative=out). Throws when the
     * resulting balance would go negative for out-movements.
     */
    public function move(
        int $ownerId,
        int $categoryId,
        string $type,
        float $qty,
        ?float $unitCost = null,
        ?string $refType = null,
        ?int $refId = null,
        ?int $agentId = null,
        ?string $note = null
    ): AccStockMovement {
        if (! in_array($type, AccStockMovement::TYPES, true)) {
            throw new AccStockException("نوع حركة غير معروف: {$type}");
        }
        if ($qty == 0.0) {
            throw new AccStockException('كمية الحركة لا يمكن أن تكون صفراً');
        }

        return DB::transaction(function () use (
            $ownerId, $categoryId, $type, $qty, $unitCost, $refType, $refId, $agentId, $note
        ) {
            $stock = AccStock::where('network_owner_id', $ownerId)
                ->where('category_id', $categoryId)
                ->lockForUpdate()
                ->first()
                ?? new AccStock([
                    'network_owner_id' => $ownerId,
                    'category_id' => $categoryId,
                    'qty' => 0,
                    'avg_cost' => 0,
                ]);

            $current = (float) $stock->qty;
            $next = $current + $qty;
            if ($next < -0.0001) {
                throw new AccStockException(
                    'الرصيد لا يكفي — المتاح ' . $this->fmt($current)
                    . ' والمطلوب ' . $this->fmt(abs($qty)),
                    409
                );
            }

            $cost = $unitCost ?? (float) $stock->avg_cost;

            // Replay guard — a retried document post must not double
            // the stock (unique index backs this check).
            if ($refType !== null && $refId !== null) {
                $exists = AccStockMovement::where('network_owner_id', $ownerId)
                    ->where('ref_type', $refType)
                    ->where('ref_id', $refId)
                    ->where('type', $type)
                    ->exists();
                if ($exists) {
                    return AccStockMovement::where('network_owner_id', $ownerId)
                        ->where('ref_type', $refType)
                        ->where('ref_id', $refId)
                        ->where('type', $type)
                        ->firstOrFail();
                }
            }

            // Weighted average cost — only incoming stock reprices.
            if ($qty > 0 && $cost > 0) {
                $base = ($current * (float) $stock->avg_cost) + ($qty * $cost);
                $stock->avg_cost = $next > 0 ? round($base / $next, 4) : $cost;
            }

            $stock->qty = $next;
            $stock->save();

            return AccStockMovement::create([
                'network_owner_id' => $ownerId,
                'category_id' => $categoryId,
                'type' => $type,
                'qty' => $qty,
                'unit_cost' => $cost,
                'ref_type' => $refType,
                'ref_id' => $refId,
                'agent_id' => $agentId,
                'note' => $note,
                'created_at' => now(),
            ]);
        });
    }

    /**
     * Absolute recount: sets the balance to exactly $newQty via a
     * signed `adjust` movement holding the delta.
     */
    public function adjust(
        AccContext $ctx,
        int $categoryId,
        float $newQty,
        ?string $note = null
    ): AccStockMovement {
        if ($newQty < 0) {
            throw new AccStockException('الرصيد الجديد لا يمكن أن يكون سالباً');
        }
        $this->ownCategory($ctx->ownerId, $categoryId);

        $stock = AccStock::where('network_owner_id', $ctx->ownerId)
            ->where('category_id', $categoryId)
            ->first();
        $delta = $newQty - (float) ($stock->qty ?? 0);

        if ($delta == 0.0) {
            throw new AccStockException('الرصيد مطابق للحالي — لا حاجة لتسوية');
        }

        return $this->move(
            $ctx->ownerId, $categoryId, 'adjust', $delta,
            null, null, null, $ctx->agentId(),
            $note ?? 'تسوية جرد إلى ' . $this->fmt($newQty)
        );
    }

    // ── Documents ────────────────────────────────────────────────

    /**
     * Purchase from a supplier: acc_purchases + `in` movement +
     * `purchase` journal (inventory ← cash or supplier payable).
     */
    public function recordPurchase(AccContext $ctx, array $data): AccPurchase
    {
        $category = $this->ownCategory($ctx->ownerId, (int) $data['category_id']);
        $qty = (float) $data['qty'];
        $unitPrice = round((float) $data['unit_price'], 2);
        $rate = (float) ($data['exchange_rate'] ?? 1);
        if ($qty <= 0 || $unitPrice < 0 || $rate <= 0) {
            throw new AccStockException('الكمية والسعر وسعر الصرف يجب أن تكون صحيحة');
        }

        $supplierId = isset($data['supplier_id']) ? (int) $data['supplier_id'] : null;
        if ($supplierId !== null) {
            $exists = \App\Models\AccSupplier::where('network_owner_id', $ctx->ownerId)
                ->whereKey($supplierId)->exists();
            if (! $exists) {
                throw new AccStockException('المورد غير موجود');
            }
        }

        $payment = $data['payment'] ?? 'cash';
        $total = round($qty * $unitPrice, 2);

        return DB::transaction(function () use (
            $ctx, $data, $category, $qty, $unitPrice, $rate, $supplierId, $payment, $total
        ) {
            $purchase = AccPurchase::create([
                'network_owner_id' => $ctx->ownerId,
                'supplier_id' => $supplierId,
                'category_id' => $category->id,
                'invoice_no' => $data['invoice_no'] ?? null,
                'qty' => $qty,
                'unit_price' => $unitPrice,
                'currency' => $data['currency'] ?? 'YER',
                'exchange_rate' => $rate,
                'total' => $total,
                'payment' => $payment,
                'date' => $data['date'] ?? now()->toDateString(),
                'agent_id' => $ctx->agentId(),
                'note' => $data['note'] ?? null,
            ]);

            $this->move(
                $ctx->ownerId, $category->id, 'in', $qty, $unitPrice,
                'acc_purchases', $purchase->id, $ctx->agentId(),
                'شراء' . ($purchase->invoice_no ? " فاتورة {$purchase->invoice_no}" : '')
            );

            $credit = $payment === 'credit'
                ? ['account_code' => AccAccount::AP_SUPPLIERS, 'party_type' => 'supplier',
                   'party_id' => $supplierId, 'debit' => 0, 'credit' => $total]
                : ['account_code' => AccAccount::CASH_MAIN,
                   'debit' => 0, 'credit' => $total];

            $this->posting->post('purchase', [
                'network_owner_id' => $ctx->ownerId,
                'agent_id' => $ctx->agentId(),
                'doc_ref_id' => $purchase->id,
                'date' => $purchase->date,
                'currency' => $purchase->currency,
                'exchange_rate' => $rate,
                'memo' => 'شراء ' . $this->fmt($qty) . ' × ' . $category->name,
                'idempotency_key' => 'acc-purchase-' . $purchase->id,
                'lines' => [
                    ['account_code' => AccAccount::INVENTORY_CARDS,
                     'debit' => $total, 'credit' => 0],
                    $credit,
                ],
            ]);

            $this->audit($ctx, 'purchase.create', 'acc_purchases', $purchase->id, [
                'qty' => $qty, 'total' => $total, 'payment' => $payment,
            ]);

            return $purchase;
        });
    }

    /**
     * Damaged/lost cards: acc_damaged + negative `damaged` movement +
     * `damaged` journal (expense ← inventory at avg cost).
     */
    public function recordDamaged(AccContext $ctx, array $data): AccDamaged
    {
        $category = $this->ownCategory($ctx->ownerId, (int) $data['category_id']);
        $qty = (float) $data['qty'];
        if ($qty <= 0) {
            throw new AccStockException('كمية التالف يجب أن تكون أكبر من صفر');
        }

        return DB::transaction(function () use ($ctx, $data, $category, $qty) {
            $unitCost = isset($data['unit_cost'])
                ? (float) $data['unit_cost']
                : (float) (AccStock::where('network_owner_id', $ctx->ownerId)
                    ->where('category_id', $category->id)->value('avg_cost') ?? 0);

            $damaged = AccDamaged::create([
                'network_owner_id' => $ctx->ownerId,
                'category_id' => $category->id,
                'qty' => $qty,
                'unit_cost' => $unitCost,
                'reason' => $data['reason'] ?? null,
                'evidence_note' => $data['evidence_note'] ?? null,
                'date' => $data['date'] ?? now()->toDateString(),
                'agent_id' => $ctx->agentId(),
            ]);

            $this->move(
                $ctx->ownerId, $category->id, 'damaged', -$qty, $unitCost,
                'acc_damaged', $damaged->id, $ctx->agentId(),
                'تالف: ' . ($data['reason'] ?? 'بدون سبب')
            );

            $cost = round($qty * $unitCost, 2);
            if ($cost > 0) {
                $this->posting->post('damaged', [
                    'network_owner_id' => $ctx->ownerId,
                    'agent_id' => $ctx->agentId(),
                    'doc_ref_id' => $damaged->id,
                    'date' => $damaged->date,
                    'memo' => 'تالف ' . $this->fmt($qty) . ' × ' . $category->name,
                    'idempotency_key' => 'acc-damaged-' . $damaged->id,
                    'lines' => [
                        ['account_code' => AccAccount::EXPENSES,
                         'debit' => $cost, 'credit' => 0],
                        ['account_code' => AccAccount::INVENTORY_CARDS,
                         'debit' => 0, 'credit' => $cost],
                    ],
                ]);
            }

            $this->audit($ctx, 'damaged.create', 'acc_damaged', $damaged->id, [
                'qty' => $qty, 'cost' => $cost,
            ]);

            return $damaged;
        });
    }

    /**
     * Return document: acc_returns + signed `return` movement +
     * `return` journal. purchase_return ships stock back OUT to the
     * supplier; sale/card returns bring it back IN.
     */
    public function recordReturn(AccContext $ctx, array $data): AccReturn
    {
        $kind = (string) $data['kind'];
        if (! in_array($kind, AccReturn::KINDS, true)) {
            throw new AccStockException('نوع مرتجع غير معروف');
        }
        $category = $this->ownCategory($ctx->ownerId, (int) $data['category_id']);
        $qty = (float) $data['qty'];
        $amount = round((float) ($data['amount'] ?? 0), 2);
        if ($qty <= 0) {
            throw new AccStockException('كمية المرتجع يجب أن تكون أكبر من صفر');
        }

        $stockIn = in_array($kind, AccReturn::IN_KINDS, true);

        return DB::transaction(function () use (
            $ctx, $data, $kind, $category, $qty, $amount, $stockIn
        ) {
            // Sale/card returns re-enter at cost basis; a purchase
            // return leaves at its supplier price (amount/qty).
            $avg = (float) (AccStock::where('network_owner_id', $ctx->ownerId)
                ->where('category_id', $category->id)->value('avg_cost') ?? 0);
            $unitCost = $kind === 'purchase_return' && $amount > 0 && $qty > 0
                ? round($amount / $qty, 4)
                : $avg;

            $return = AccReturn::create([
                'network_owner_id' => $ctx->ownerId,
                'kind' => $kind,
                'ref_type' => $data['ref_type'] ?? null,
                'ref_id' => $data['ref_id'] ?? null,
                'category_id' => $category->id,
                'qty' => $qty,
                'amount' => $amount,
                'reason' => $data['reason'] ?? null,
                'date' => $data['date'] ?? now()->toDateString(),
                'agent_id' => $ctx->agentId(),
            ]);

            $this->move(
                $ctx->ownerId, $category->id, 'return',
                $stockIn ? $qty : -$qty, $unitCost,
                'acc_returns', $return->id, $ctx->agentId(),
                'مرتجع: ' . ($data['reason'] ?? $kind)
            );

            $this->postReturnEntry($ctx, $return, $category, $qty, $amount, $unitCost, $stockIn);

            $this->audit($ctx, 'return.create', 'acc_returns', $return->id, [
                'kind' => $kind, 'qty' => $qty, 'amount' => $amount,
            ]);

            return $return;
        });
    }

    /** Journal legs per return kind — see class docblock. */
    private function postReturnEntry(
        AccContext $ctx, AccReturn $return, AccCardCategory $category,
        float $qty, float $amount, float $unitCost, bool $stockIn
    ): void {
        $cost = round($qty * $unitCost, 2);
        $lines = [];

        if ($return->kind === 'purchase_return') {
            $value = $amount > 0 ? $amount : $cost;
            if ($value <= 0) {
                return;
            }
            // The payable leg carries a supplier party only when the
            // caller explicitly references one (ref_type=acc_suppliers).
            $party = $return->ref_type === 'acc_suppliers' && $return->ref_id !== null
                ? ['party_type' => 'supplier', 'party_id' => $return->ref_id]
                : ['party_type' => null, 'party_id' => null];
            $lines = [
                ['account_code' => AccAccount::AP_SUPPLIERS,
                 ...$party, 'debit' => $value, 'credit' => 0],
                ['account_code' => AccAccount::INVENTORY_CARDS,
                 'debit' => 0, 'credit' => $value],
            ];
        } elseif ($return->kind === 'sale_return') {
            // Refund liability to the customer + inventory back at cost.
            if ($amount > 0) {
                $lines[] = ['account_code' => AccAccount::REVENUE_SALES,
                            'debit' => $amount, 'credit' => 0];
                $lines[] = ['account_code' => AccAccount::CUSTOMER_BALANCES,
                            'debit' => 0, 'credit' => $amount];
            }
            if ($cost > 0) {
                $lines[] = ['account_code' => AccAccount::INVENTORY_CARDS,
                            'debit' => $cost, 'credit' => 0];
                $lines[] = ['account_code' => AccAccount::EXPENSES,
                            'debit' => 0, 'credit' => $cost];
            }
        } else { // card_return — stock back without a financial leg.
            if ($cost <= 0) {
                return;
            }
            $lines = [
                ['account_code' => AccAccount::INVENTORY_CARDS,
                 'debit' => $cost, 'credit' => 0],
                ['account_code' => AccAccount::EQUITY,
                 'debit' => 0, 'credit' => $cost],
            ];
        }

        if (count($lines) < 2) {
            return;
        }

        $this->posting->post('return', [
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'doc_ref_id' => $return->id,
            'date' => $return->date,
            'memo' => 'مرتجع ' . $this->fmt($qty) . ' × ' . $category->name,
            'idempotency_key' => 'acc-return-' . $return->id,
            'lines' => $lines,
        ]);
    }

    // ── MikroTik router-card auto-sync (read-only on `cards`) ────

    /**
     * Reconcile platform `cards` rows with source='mikrotik' into
     * accounting stock. Every router card gets an `in` movement;
     * already-sold/expired cards additionally get their out movement
     * so acc_stock mirrors physical availability. Idempotent — the
     * (ref_type='card', ref_id, type) unique index makes replays free.
     *
     * @return array{scanned:int, imported:int, sold:int, skipped:int}
     */
    public function syncRouterCards(AccContext $ctx): array
    {
        $stats = ['scanned' => 0, 'imported' => 0, 'sold' => 0, 'skipped' => 0];
        if (! Schema::hasTable('cards') || ! Schema::hasTable('networks')
            || ! Schema::hasColumn('cards', 'source')) {
            return $stats;
        }

        $networkIds = DB::table('networks')->where('user_id', $ctx->ownerId)->pluck('id');
        if ($networkIds->isEmpty()) {
            return $stats;
        }

        $cards = DB::table('cards')
            ->whereIn('network_id', $networkIds)
            ->where('source', 'mikrotik')
            ->orderBy('id')
            ->get(['id', 'category_id', 'status']);
        $stats['scanned'] = $cards->count();
        if ($cards->isEmpty()) {
            return $stats;
        }

        $existing = AccStockMovement::where('network_owner_id', $ctx->ownerId)
            ->where('ref_type', 'card')
            ->get(['ref_id', 'type'])
            ->groupBy('ref_id')
            ->map(fn ($g) => $g->pluck('type')->all());

        return DB::transaction(function () use ($ctx, $cards, $existing, &$stats) {
            $catCache = [];

            foreach ($cards as $card) {
                $moves = $existing->get($card->id) ?? [];
                $outType = match ($card->status) {
                    'sold' => 'sale',
                    'expired' => 'out',
                    default => null,
                };

                if (in_array('in', $moves, true)
                    && ($outType === null || in_array($outType, $moves, true))) {
                    $stats['skipped']++;
                    continue;
                }

                $catId = $catCache[$card->category_id]
                    ??= $this->accCategoryForPlatform($ctx->ownerId, (int) $card->category_id)->id;

                if (! in_array('in', $moves, true)) {
                    $this->move(
                        $ctx->ownerId, $catId, 'in', 1,
                        null, 'card', $card->id, $ctx->agentId(),
                        'كرت راوتر تلقائي'
                    );
                    $stats['imported']++;
                }
                if ($outType !== null && ! in_array($outType, $moves, true)) {
                    $this->move(
                        $ctx->ownerId, $catId, $outType, -1,
                        null, 'card', $card->id, $ctx->agentId(),
                        'كرت راوتر ' . ($card->status === 'sold' ? 'مُباع' : 'منتهي')
                    );
                    if ($outType === 'sale') {
                        $stats['sold']++;
                    }
                }
            }

            if ($stats['imported'] > 0 || $stats['sold'] > 0) {
                AccCardImport::create([
                    'network_owner_id' => $ctx->ownerId,
                    'source' => 'mikrotik',
                    'filename' => 'router-auto-sync',
                    'rows_count' => $stats['scanned'],
                    'imported_count' => $stats['imported'],
                    'skipped_count' => $stats['skipped'],
                    'status' => 'processed',
                    'agent_id' => $ctx->agentId(),
                ]);

                $this->audit($ctx, 'stock.sync_mikrotik', 'acc_stock', 0, $stats);
            }

            return $stats;
        });
    }

    /**
     * Map a platform `card_categories` row to its acc bucket — first
     * by explicit binding, then by name; when nothing matches a
     * $binding-bound category is created on the fly so no card is
     * ever dropped. $binding is 'mikrotik' for the router sync and
     * 'platform' for ACC-08's customer-app sale poster.
     */
    public function accCategoryForPlatform(
        int $ownerId,
        int $platformCatId,
        string $binding = 'mikrotik'
    ): AccCardCategory {
        $bound = AccCardCategory::where('network_owner_id', $ownerId)
            ->where('card_category_id', $platformCatId)
            ->first();
        if ($bound !== null) {
            return $bound;
        }

        $platform = Schema::hasTable('card_categories')
            ? DB::table('card_categories')->find($platformCatId)
            : null;

        if ($platform !== null) {
            $byName = AccCardCategory::where('network_owner_id', $ownerId)
                ->where('name', $platform->name)
                ->whereIn('source_binding', [$binding, 'any'])
                ->first();
            if ($byName !== null) {
                $byName->card_category_id = $platformCatId;
                $byName->save();

                return $byName;
            }
        }

        return AccCardCategory::create([
            'network_owner_id' => $ownerId,
            'name' => $platform->name
                ?? ('فئة ' . ($binding === 'platform' ? 'منصة' : 'راوتر') . ' ' . $platformCatId),
            'sell_price' => (float) ($platform->price ?? 0),
            'cost_price' => 0,
            'unit_label' => 'كرت',
            'source_binding' => $binding,
            'card_category_id' => $platformCatId,
            'is_active' => true,
        ]);
    }

    // ── Bulk CSV intake ──────────────────────────────────────────

    /**
     * File-based stock intake: CSV rows (name, qty, unit_cost,
     * sell_price?) upsert categories by name and post `in` movements.
     * The whole run is audited in acc_card_imports with per-row errors.
     *
     * @return array{import:AccCardImport, movements:int}
     */
    public function importCsv(AccContext $ctx, string $content, string $filename): AccCardImport
    {
        $rows = $this->parseCsv($content);
        $imported = 0;
        $skipped = 0;
        $errors = [];

        foreach ($rows as $i => $row) {
            try {
                $name = trim((string) ($row['name'] ?? ''));
                $qty = (float) ($row['qty'] ?? 0);
                if ($name === '' || $qty <= 0) {
                    throw new AccStockException('اسم أو كمية غير صالحة');
                }

                $category = AccCardCategory::firstOrCreate(
                    ['network_owner_id' => $ctx->ownerId, 'name' => $name],
                    [
                        'sell_price' => (float) ($row['sell_price'] ?? 0),
                        'cost_price' => (float) ($row['unit_cost'] ?? 0),
                        'source_binding' => 'any',
                        'is_active' => true,
                    ]
                );

                $this->move(
                    $ctx->ownerId, $category->id, 'in', $qty,
                    isset($row['unit_cost']) ? (float) $row['unit_cost'] : null,
                    null, null, $ctx->agentId(),
                    'استيراد ملف ' . $filename
                );
                $imported++;
            } catch (\Throwable $e) {
                $skipped++;
                $errors[] = ['row' => $i + 1, 'error' => $e->getMessage()];
            }
        }

        $import = AccCardImport::create([
            'network_owner_id' => $ctx->ownerId,
            'source' => 'file',
            'filename' => $filename,
            'rows_count' => count($rows),
            'imported_count' => $imported,
            'skipped_count' => $skipped,
            'status' => $skipped === 0 ? 'processed' : ($imported === 0 ? 'failed' : 'partial'),
            'errors' => $errors === [] ? null : $errors,
            'agent_id' => $ctx->agentId(),
        ]);

        $this->audit($ctx, 'stock.import_csv', 'acc_card_imports', $import->id, [
            'rows' => count($rows), 'imported' => $imported, 'skipped' => $skipped,
        ]);

        return $import;
    }

    /** @return list<array{name?:string,qty?:string,unit_cost?:string,sell_price?:string}> */
    private function parseCsv(string $content): array
    {
        $lines = preg_split('/\r\n|\r|\n/', trim($content)) ?: [];
        if ($lines === []) {
            return [];
        }

        $header = str_getcsv(array_shift($lines));
        $map = array_map(fn ($h) => trim(mb_strtolower((string) $h)), $header);

        $rows = [];
        foreach ($lines as $line) {
            if (trim($line) === '') {
                continue;
            }
            $cells = str_getcsv($line);
            $row = [];
            foreach ($map as $idx => $key) {
                $row[$key] = $cells[$idx] ?? null;
            }
            // Tolerate headerless files: name,qty,cost order.
            if (! isset($row['name'])) {
                $row = [
                    'name' => $cells[0] ?? null,
                    'qty' => $cells[1] ?? null,
                    'unit_cost' => $cells[2] ?? null,
                    'sell_price' => $cells[3] ?? null,
                ];
            }
            $rows[] = $row;
        }

        return $rows;
    }

    // ── Helpers ──────────────────────────────────────────────────

    public function ownCategory(int $ownerId, int $categoryId): AccCardCategory
    {
        $cat = AccCardCategory::where('network_owner_id', $ownerId)->find($categoryId);
        if ($cat === null) {
            throw new AccStockException('الفئة غير موجودة', 404);
        }

        return $cat;
    }

    private function audit(AccContext $ctx, string $action, string $entity, int $entityId, array $meta = []): void
    {
        AccAuditLog::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'action' => $action,
            'entity' => $entity,
            'entity_id' => $entityId,
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }

    private function fmt(float $n): string
    {
        return rtrim(rtrim(number_format($n, 2, '.', ''), '0'), '.');
    }
}
