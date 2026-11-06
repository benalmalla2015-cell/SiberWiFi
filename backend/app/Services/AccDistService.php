<?php

namespace App\Services;

use App\Models\AccAccount;
use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\AccCashBox;
use App\Models\AccCollection;
use App\Models\AccCommission;
use App\Models\AccDebt;
use App\Models\AccPosPoint;
use App\Models\AccProfitLedger;
use App\Models\AccSale;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-06 — the distributor document cycle (PLAN §1 + §2.2 + §3).
 *
 * sale(): ONE atomic DB transaction —
 *   1) acc_sales + acc_sale_items (sale_no, replayable key)
 *   2) stock out per catalog item (type `sale`) — insufficient
 *      stock aborts and rolls everything back
 *   3) daily-limit + credit-limit + cash/credit policy checks
 *   4) balanced `sale` journal entry via AccPostingService:
 *      Dr box(paid) + Dr AR_POS(remainder) / Cr sales revenue
 *      + COGS legs + distributor commission legs
 *   5) acc_debts row for the unpaid remainder (post_entry=false —
 *      the sale entry already booked the AR leg)
 *   6) acc_profit_ledger + acc_commissions accrual
 *   7) acc_audit_log
 *
 * home()/report()/commissions() are the read models behind
 * GET /dist/home · /dist/report · /dist/commissions.
 *
 * Currency rule (PLAN §2.5 — same as ACC-05): documents carry
 * their own currency; acc_balances posts the north-normalized base.
 */
class AccDistService
{
    private const BASE_CURRENCY = 'north';

    public function __construct(
        private AccPostingService $posting,
        private AccDiscountService $discounts,
        private AccTierRewardWriter $tierRewards,
    ) {}

    // ── Sale (the atomic cycle) ──────────────────────────────────

    /**
     * Payload: pos_id, items[{category_id?, name?, qty, unit_price?,
     * unit_cost?}], payment_kind cash|credit|partial, paid_amount?,
     * currency?, cash_box_id?, due_date?, distributor_id?, sold_at?,
     * note?, idempotency_key?
     */
    public function sale(AccContext $ctx, array $data): AccSale
    {
        $key = $this->idempotencyKey($data);
        if ($key !== null) {
            $existing = AccSale::where('idempotency_key', $key)->first();
            if ($existing) {
                return $existing->load('items');
            }
        }

        $pos = $this->resolvePos($ctx, (int) ($data['pos_id'] ?? 0));
        $distributor = $this->resolveDistributor($ctx, $data);
        $items = $this->resolveItems($ctx->ownerId, $data['items'] ?? []);
        $currency = $this->currency($data['currency'] ?? null);

        $total = round(array_sum(array_column($items, 'line_total')), 2);
        if ($total <= 0) {
            throw new AccDistException('إجمالي البيع يجب أن يكون أكبر من صفر');
        }

        // ACC-10 — tier rewards resolve on the gross document value:
        // a direct_percent tier discounts the payable, points/profit
        // tiers credit the POS, a commission tier bumps the agent's
        // accrual — all applied inside the sale transaction below.
        $qty = (float) array_sum(array_column($items, 'qty'));
        $rewards = $this->discounts->rewards($ctx->ownerId, $qty, $total);
        $discount = min($rewards['discount'], $total);
        $netTotal = round($total - $discount, 2);

        [$kind, $paid] = $this->resolvePayment($data, $netTotal);
        $this->assertPaymentAllowed($distributor, $paid, $netTotal);
        $this->assertDailyLimits($distributor, $items, $ctx->ownerId);

        $attempts = 0;
        do {
            try {
                return DB::transaction(function () use (
                    $ctx, $data, $key, $pos, $distributor, $items,
                    $currency, $total, $netTotal, $discount, $rewards, $kind, $paid
                ) {
                    $soldAt = $this->timestamp($data['sold_at'] ?? null);
                    $creditPart = round($netTotal - $paid, 2);

                    // POS credit limit (0 = مفتوح — لا حد).
                    if ($creditPart > 0 && (float) $pos->credit_limit > 0) {
                        $open = $this->posting->balanceOf($ctx->ownerId, 'pos', $pos->id);
                        if ($open + $creditPart > (float) $pos->credit_limit + 0.005) {
                            throw new AccDistException(
                                "تجاوز سقف الآجل — حد النقطة {$pos->credit_limit} والمفتوح حالياً {$open}"
                            );
                        }
                    }

                    // total_amount stores the payable after discount;
                    // the gross value = total_amount + discount_amount.
                    $saleData = [
                        'network_owner_id' => $ctx->ownerId,
                        'sale_no' => $this->nextSaleNo($ctx->ownerId),
                        'pos_id' => $pos->id,
                        'distributor_id' => $distributor?->id,
                        'agent_id' => $ctx->agentId(),
                        'payment_kind' => $kind,
                        'total_amount' => $netTotal,
                        'paid_amount' => $paid,
                        'currency' => $currency,
                        'exchange_rate' => $this->rateToBase($currency),
                        'base_total' => $this->toBase($netTotal, $currency),
                        'base_paid' => $this->toBase($paid, $currency),
                        'status' => AccSale::STATUS_POSTED,
                        'sold_at' => $soldAt,
                        'note' => $data['note'] ?? null,
                        'idempotency_key' => $key,
                    ];
                    if ($discount > 0 && Schema::hasColumn('acc_sales', 'discount_amount')) {
                        $saleData['discount_amount'] = $discount;
                    }
                    $sale = AccSale::create($saleData);

                    foreach ($items as $item) {
                        $sale->items()->create($item);
                    }

                    $this->applyStockOut($ctx, $sale, $items);

                    $box = $paid > 0
                        ? $this->resolveBox($ctx, $data['cash_box_id'] ?? null, $currency)
                        : null;

                    // The credit remainder becomes a tracked debt on
                    // the POS — the sale entry books its AR leg, so
                    // the debt posts no opening entry of its own.
                    $debt = null;
                    if ($creditPart > 0) {
                        $debt = AccDebt::create([
                            'network_owner_id' => $ctx->ownerId,
                            'party_type' => 'pos',
                            'party_id' => $pos->id,
                            'party_name' => $pos->name,
                            'phone' => $pos->phone,
                            'amount_due' => $creditPart,
                            'amount_paid' => 0,
                            'base_due' => $this->toBase($creditPart, $currency),
                            'base_paid' => 0,
                            'currency' => $currency,
                            'exchange_rate' => $this->rateToBase($currency),
                            'status' => AccDebt::STATUS_OPEN,
                            'due_date' => $data['due_date'] ?? null,
                            'agent_id' => $ctx->agentId(),
                            'note' => 'آجل بيع ' . $sale->sale_no,
                        ]);
                    }

                    // Tier commission stacks on the agent's own
                    // commission (percent reads the net value).
                    $commission = $this->commissionOf($distributor, $netTotal)
                        + $rewards['commission'];
                    $entry = $this->postEntry(
                        $ctx, $sale, $pos, $items, $distributor,
                        $commission, $box, $paid, $creditPart, $currency
                    );

                    if ($box !== null) {
                        $this->addToBox($box, $this->toBoxAmount($paid, $currency, $box));
                        $sale->cash_box_id = $box->id;
                    }
                    if ($debt !== null) {
                        $debt->journal_entry_id = $entry->id;
                        $debt->save();
                        $sale->debt_id = $debt->id;
                    }
                    $sale->journal_entry_id = $entry->id;
                    $sale->commission_amount = $commission;
                    $sale->save();

                    if ($commission > 0 && $distributor !== null) {
                        AccProfitLedger::create([
                            'network_owner_id' => $ctx->ownerId,
                            'party_type' => 'distributor',
                            'party_id' => $distributor->id,
                            'reason' => 'sale_commission',
                            'delta' => $commission,
                            'ref_type' => 'acc_sales',
                            'ref_id' => $sale->id,
                            'agent_id' => $ctx->agentId(),
                            'note' => 'عمولة بيع ' . $sale->sale_no,
                            'created_at' => now(),
                        ]);
                        AccCommission::accrue(
                            $ctx->ownerId,
                            $distributor->id,
                            $soldAt->format('Y-m'),
                            $netTotal,
                            $commission
                        );
                    }

                    // ACC-10 — points/profit tier bonuses credit the
                    // buying POS inside this same transaction.
                    $this->tierRewards->credit($ctx, $pos, 'acc_sales',
                        $sale->id, $sale->sale_no, $rewards);

                    $this->audit($ctx, 'dist.sale', 'acc_sales', $sale->id, [
                        'sale_no' => $sale->sale_no,
                        'pos' => $pos->id,
                        'kind' => $kind,
                        'total' => $netTotal,
                        'discount' => $discount,
                        'paid' => $paid,
                        'currency' => $currency,
                        'commission' => $commission,
                        'tiers' => array_map(
                            fn ($t) => $t->id, $rewards['tiers']
                        ),
                    ]);

                    return $sale->load('items');
                });
            } catch (QueryException $e) {
                if ($key !== null) {
                    $existing = AccSale::where('idempotency_key', $key)->first();
                    if ($existing) {
                        return $existing->load('items');
                    }
                }
                if (++$attempts >= 3 || ! $this->isUniqueViolation($e)) {
                    throw $e;
                }
                // sale_no race — retry with a fresh sequence lookup.
            }
        } while (true);
    }

    // ── Home (the distributor landing read model) ────────────────

    /**
     * Categories with live stock + the agent's daily remaining,
     * sellable POS points with their balances, and today's totals.
     */
    public function home(AccContext $ctx): array
    {
        $agent = $ctx->role === 'distributor' ? $ctx->agent : null;
        $limits = $agent?->daily_limit_per_category ?? [];
        $soldToday = $this->soldTodayByCategory($ctx->ownerId, $agent?->id);

        $categories = collect();
        if (Schema::hasTable('acc_card_categories')) {
            $categories = DB::table('acc_card_categories')
                ->where('network_owner_id', $ctx->ownerId)
                ->where('is_active', true)
                ->orderBy('sort_order')
                ->orderBy('id')
                ->get();
        }

        $stock = Schema::hasTable('acc_stock')
            ? DB::table('acc_stock')
                ->where('network_owner_id', $ctx->ownerId)
                ->pluck('qty', 'category_id')
            : collect();

        $categories = $categories->map(function ($cat) use ($limits, $soldToday, $stock) {
            $limit = $limits[$cat->id] ?? $limits[(string) $cat->id] ?? null;
            $limit = is_numeric($limit) ? (float) $limit : null;
            $sold = (float) ($soldToday[$cat->id] ?? 0);

            return [
                'id' => (int) $cat->id,
                'name' => $cat->name,
                'unit_label' => $cat->unit_label ?? 'كرت',
                'sell_price' => (float) $cat->sell_price,
                'stock_qty' => (float) ($stock[$cat->id] ?? 0),
                'daily_limit' => $limit,
                'sold_today' => $sold,
                'remaining_today' => $limit === null ? null : max(0.0, $limit - $sold),
            ];
        })->values();

        $posPoints = AccPosPoint::where('network_owner_id', $ctx->ownerId)
            ->where('status', AccPosPoint::STATUS_ACTIVE)
            ->orderBy('name')
            ->get()
            ->map(fn (AccPosPoint $p) => [
                'id' => $p->id,
                'name' => $p->name,
                'location' => $p->location,
                'phone' => $p->phone,
                'points_balance' => (float) $p->points_balance,
                'profit_balance' => (float) $p->profit_balance,
                'credit_limit' => (float) $p->credit_limit,
                'ar_balance' => $this->posting->balanceOf($ctx->ownerId, 'pos', $p->id),
            ])
            ->values();

        return [
            'agent' => $agent === null ? null : [
                'id' => $agent->id,
                'display_name' => $agent->display_name,
                'cash_allowed' => (bool) $agent->cash_allowed,
                'credit_allowed' => (bool) $agent->credit_allowed,
                'commission_mode' => $agent->commission_mode,
                'commission_value' => (float) $agent->commission_value,
            ],
            'today' => $this->todayTotals($ctx, $agent?->id),
            'categories' => $categories,
            'pos_points' => $posPoints,
        ];
    }

    // ── Report ───────────────────────────────────────────────────

    /** The distributor's own book over a period (default: today). */
    public function report(AccContext $ctx, ?string $from, ?string $to): array
    {
        $fromDate = $from ? Carbon::parse($from)->startOfDay() : Carbon::today()->startOfDay();
        $toDate = $to ? Carbon::parse($to)->endOfDay() : Carbon::today()->endOfDay();

        $sales = AccSale::where('network_owner_id', $ctx->ownerId)
            ->where('status', AccSale::STATUS_POSTED)
            ->whereBetween('sold_at', [$fromDate, $toDate])
            ->tap($this->salesScope($ctx))
            ->get(['id', 'sale_no', 'pos_id', 'payment_kind', 'total_amount',
                'paid_amount', 'base_total', 'base_paid', 'sold_at']);

        $saleIds = $sales->pluck('id');
        $byCategory = $saleIds->isEmpty()
            ? collect()
            : DB::table('acc_sale_items')
                ->whereIn('sale_id', $saleIds)
                ->selectRaw('category_id, category_name, SUM(qty) as qty, SUM(line_total) as amount')
                ->groupBy('category_id', 'category_name')
                ->orderByDesc('amount')
                ->get();

        $collections = AccCollection::where('network_owner_id', $ctx->ownerId)
            ->whereBetween('collected_at', [$fromDate, $toDate])
            ->when($ctx->role === 'distributor' && $ctx->agentId() !== null,
                fn ($q) => $q->where('collector_agent_id', $ctx->agentId()))
            ->sum('base_amount');

        $openDebts = AccDebt::where('network_owner_id', $ctx->ownerId)
            ->where('party_type', 'pos')
            ->whereIn('status', [AccDebt::STATUS_OPEN, AccDebt::STATUS_PARTIAL])
            ->when($ctx->role === 'distributor' && $ctx->agentId() !== null,
                fn ($q) => $q->where('agent_id', $ctx->agentId()))
            ->selectRaw('COUNT(*) as cnt, COALESCE(SUM(base_due - base_paid), 0) as remaining')
            ->first();

        $daily = $sales->groupBy(fn (AccSale $s) => $s->sold_at->toDateString())
            ->map(fn ($rows, $date) => [
                'date' => $date,
                'count' => $rows->count(),
                'total' => round((float) $rows->sum('base_total'), 2),
                'cash' => round((float) $rows->sum('base_paid'), 2),
                'credit' => round((float) $rows->sum('base_total') - (float) $rows->sum('base_paid'), 2),
            ])
            ->sortKeys()
            ->values();

        return [
            'from' => $fromDate->toDateString(),
            'to' => $toDate->toDateString(),
            'totals' => [
                'sales_count' => $sales->count(),
                'sales_total' => round((float) $sales->sum('base_total'), 2),
                'cash_total' => round((float) $sales->sum('base_paid'), 2),
                'credit_total' => round(
                    (float) $sales->sum('base_total') - (float) $sales->sum('base_paid'), 2
                ),
                'collections_total' => round((float) $collections, 2),
                'open_debts_count' => (int) ($openDebts->cnt ?? 0),
                'open_debts_remaining' => round((float) ($openDebts->remaining ?? 0), 2),
            ],
            'daily' => $daily,
            'categories' => $byCategory->map(fn ($r) => [
                'category_id' => $r->category_id !== null ? (int) $r->category_id : null,
                'category_name' => $r->category_name,
                'qty' => (float) $r->qty,
                'amount' => (float) $r->amount,
            ])->values(),
        ];
    }

    /** Commission period rows — own for a distributor, all for a manager. */
    public function commissions(AccContext $ctx, ?string $period): array
    {
        $query = AccCommission::with('distributor:id,display_name')
            ->where('network_owner_id', $ctx->ownerId)
            ->orderByDesc('period');

        if ($ctx->role === 'distributor' && $ctx->agentId() !== null) {
            $query->where('distributor_id', $ctx->agentId());
        }
        if ($period !== null && preg_match('/^\d{4}-\d{2}$/', $period)) {
            $query->where('period', $period);
        }

        return $query->get()->map(fn (AccCommission $c) => [
            'id' => $c->id,
            'distributor_id' => $c->distributor_id,
            'distributor_name' => $c->distributor?->display_name,
            'period' => $c->period,
            'sales_amount' => (float) $c->sales_amount,
            'commission_amount' => (float) $c->commission_amount,
            'status' => $c->status,
            'paid_at' => $c->paid_at?->toISOString(),
        ])->values()->all();
    }

    // ── Internals ────────────────────────────────────────────────

    private function resolvePos(AccContext $ctx, int $posId): AccPosPoint
    {
        $pos = AccPosPoint::where('network_owner_id', $ctx->ownerId)->find($posId);
        if ($pos === null) {
            throw new AccDistException('نقطة البيع غير موجودة');
        }
        if ($pos->status !== AccPosPoint::STATUS_ACTIVE) {
            throw new AccDistException('نقطة البيع موقوفة');
        }

        return $pos;
    }

    /**
     * A distributor always sells as himself; a manager may attach a
     * distributor for limits/commission, else sells owner-direct.
     */
    private function resolveDistributor(AccContext $ctx, array $data): ?AccAgent
    {
        if ($ctx->role === 'distributor') {
            return $ctx->agent;
        }
        $id = (int) ($data['distributor_id'] ?? 0);
        if ($id <= 0) {
            return null;
        }
        $agent = AccAgent::where('network_owner_id', $ctx->ownerId)
            ->where('role', 'distributor')
            ->where('status', AccAgent::STATUS_ACTIVE)
            ->find($id);
        if ($agent === null) {
            throw new AccDistException('الموزع المحدد غير صالح');
        }

        return $agent;
    }

    /**
     * Server-authoritative pricing: the ACC-02 catalog wins whenever
     * the row exists — a client may never set its own sell price.
     */
    private function resolveItems(int $ownerId, mixed $raw): array
    {
        if (! is_array($raw) || $raw === []) {
            throw new AccDistException('البيع يتطلب صنفاً واحداً على الأقل');
        }

        $catalog = Schema::hasTable('acc_card_categories')
            ? DB::table('acc_card_categories')
                ->where('network_owner_id', $ownerId)
                ->get()
                ->keyBy('id')
            : collect();

        $items = [];
        foreach (array_values($raw) as $i => $row) {
            if (! is_array($row)) {
                throw new AccDistException("السطر {$i}: صيغة صنف غير صحيحة");
            }
            $qty = (int) ($row['qty'] ?? 0);
            if ($qty < 1) {
                throw new AccDistException("السطر {$i}: الكمية يجب أن تكون 1 فأكثر");
            }

            $categoryId = isset($row['category_id']) && $row['category_id'] !== ''
                ? (int) $row['category_id'] : null;
            $cat = $categoryId !== null ? $catalog->get($categoryId) : null;
            if ($categoryId !== null && $catalog->isNotEmpty() && $cat === null) {
                throw new AccDistException("السطر {$i}: فئة غير موجودة");
            }
            if ($cat !== null && ! $cat->is_active) {
                throw new AccDistException("السطر {$i}: فئة «{$cat->name}» موقوفة");
            }

            $name = $cat->name ?? ($row['name'] ?? null);
            $unitPrice = isset($cat->sell_price)
                ? (float) $cat->sell_price
                : (float) ($row['unit_price'] ?? 0);
            $unitCost = isset($cat->cost_price)
                ? (float) $cat->cost_price
                : (float) ($row['unit_cost'] ?? 0);

            if ($name === null || $name === '') {
                throw new AccDistException("السطر {$i}: اسم الصنف مطلوب");
            }
            if ($unitPrice < 0 || $unitCost < 0) {
                throw new AccDistException("السطر {$i}: مبالغ سالبة مرفوضة");
            }

            $items[] = [
                'category_id' => $categoryId,
                'category_name' => $name,
                'qty' => $qty,
                'unit_price' => $unitPrice,
                'unit_cost' => $unitCost,
                'line_total' => round($qty * $unitPrice, 2),
            ];
        }

        return $items;
    }

    /** @return array{0: string, 1: float} payment kind + paid amount. */
    private function resolvePayment(array $data, float $total): array
    {
        $kind = (string) ($data['payment_kind'] ?? '');
        if (! in_array($kind, AccSale::KINDS, true)) {
            throw new AccDistException('نوع الدفع غير معروف — نقد أو آجل أو جزئي');
        }

        $paid = match ($kind) {
            AccSale::KIND_CASH => $total,
            AccSale::KIND_CREDIT => 0.0,
            default => round((float) ($data['paid_amount'] ?? 0), 2),
        };

        if ($kind === AccSale::KIND_PARTIAL && ($paid <= 0 || $paid >= $total)) {
            throw new AccDistException('البيع الجزئي يتطلب مبلغاً مدفوعاً أقل من الإجمالي');
        }
        if ($paid < 0 || $paid > $total) {
            throw new AccDistException('المبلغ المدفوع خارج نطاق الإجمالي');
        }

        return [$kind, $paid];
    }

    /** cash/credit capability flags bind distributors, not managers. */
    private function assertPaymentAllowed(?AccAgent $distributor, float $paid, float $total): void
    {
        if ($distributor === null) {
            return;
        }
        if ($paid > 0 && ! $distributor->cash_allowed) {
            throw new AccDistException('التحصيل النقدي غير مسموح لهذا الموزع', 403);
        }
        if ($total - $paid > 0.005 && ! $distributor->credit_allowed) {
            throw new AccDistException('البيع الآجل غير مسموح لهذا الموزع', 403);
        }
    }

    /**
     * Enforce the agent's daily_limit_per_category {category_id: qty}
     * — absent/null = unlimited. Sold counts today's posted sales.
     */
    private function assertDailyLimits(?AccAgent $distributor, array $items, int $ownerId): void
    {
        if ($distributor === null) {
            return;
        }
        $limits = $distributor->daily_limit_per_category ?? [];
        if ($limits === []) {
            return;
        }

        $wanted = [];
        foreach ($items as $item) {
            if ($item['category_id'] !== null) {
                $wanted[$item['category_id']] = ($wanted[$item['category_id']] ?? 0) + $item['qty'];
            }
        }

        $soldToday = $this->soldTodayByCategory($ownerId, $distributor->id);

        foreach ($wanted as $catId => $qty) {
            $limit = $limits[$catId] ?? $limits[(string) $catId] ?? null;
            if (! is_numeric($limit)) {
                continue;
            }
            $sold = (float) ($soldToday[$catId] ?? 0);
            if ($sold + $qty > (float) $limit) {
                throw new AccDistException(
                    "تجاوز الحد اليومي — المباع اليوم {$sold} والمطلوب {$qty} والحد {$limit}"
                );
            }
        }
    }

    /** qty sold today per category_id for one distributor (or tenant). */
    private function soldTodayByCategory(int $ownerId, ?int $distributorId): array
    {
        return DB::table('acc_sale_items')
            ->join('acc_sales', 'acc_sale_items.sale_id', '=', 'acc_sales.id')
            ->where('acc_sales.network_owner_id', $ownerId)
            ->where('acc_sales.status', AccSale::STATUS_POSTED)
            ->whereDate('acc_sales.sold_at', Carbon::today())
            ->when($distributorId !== null,
                fn ($q) => $q->where('acc_sales.distributor_id', $distributorId))
            ->whereNotNull('acc_sale_items.category_id')
            ->groupBy('acc_sale_items.category_id')
            ->selectRaw('acc_sale_items.category_id AS cid, SUM(acc_sale_items.qty) AS qty')
            ->pluck('qty', 'cid')
            ->all();
    }

    /** Stock-out per catalog item — a shortage aborts everything. */
    private function applyStockOut(AccContext $ctx, AccSale $sale, array $items): void
    {
        if (! Schema::hasTable('acc_stock') || ! Schema::hasTable('acc_stock_movements')) {
            return;
        }

        foreach ($items as $item) {
            if ($item['category_id'] === null) {
                continue;
            }

            $stock = DB::table('acc_stock')
                ->where('network_owner_id', $ctx->ownerId)
                ->where('category_id', $item['category_id'])
                ->lockForUpdate()
                ->first();
            $available = (float) ($stock->qty ?? 0);
            if ($available < $item['qty']) {
                throw new AccDistException(
                    "مخزون غير كافٍ لـ «{$item['category_name']}» — المتاح {$available} والمطلوب {$item['qty']}"
                );
            }

            DB::table('acc_stock')
                ->where('id', $stock->id)
                ->update(['qty' => $available - $item['qty'], 'updated_at' => now()]);

            DB::table('acc_stock_movements')->insert([
                'network_owner_id' => $ctx->ownerId,
                'category_id' => $item['category_id'],
                'type' => 'sale',
                'qty' => -$item['qty'], // signed: negative = out
                'unit_cost' => (float) $item['unit_cost'],
                'ref_type' => 'acc_sales',
                'ref_id' => $sale->id,
                'agent_id' => $ctx->agentId(),
                'note' => 'بيع ' . $sale->sale_no,
                'created_at' => now(),
            ]);
        }
    }

    /**
     * The balanced `sale` entry: paid part debits the cash box, the
     * remainder debits the POS receivable, revenue credits once,
     * COGS moves inventory to expense, and the distributor's
     * commission accrues as a POS-profit liability — one post, one
     * transaction (nested savepoint inside the sale cycle).
     */
    private function postEntry(
        AccContext $ctx,
        AccSale $sale,
        AccPosPoint $pos,
        array $items,
        ?AccAgent $distributor,
        float $commission,
        ?AccCashBox $box,
        float $paid,
        float $creditPart,
        string $currency
    ): \App\Models\AccJournalEntry {
        $baseTotal = (float) $sale->base_total;
        $basePaid = (float) $sale->base_paid;
        $baseCredit = round($baseTotal - $basePaid, 2);
        $cost = round(array_sum(array_map(
            fn ($i) => $i['qty'] * $i['unit_cost'], $items
        )), 2);
        $baseCommission = $this->toBase($commission, $currency);

        $lines = [];
        if ($basePaid > 0 && $box !== null) {
            $lines[] = [
                'account_code' => AccAccount::CASH_MAIN,
                'party_type' => 'box', 'party_id' => $box->id,
                'debit' => $basePaid, 'credit' => 0,
            ];
        }
        if ($baseCredit > 0) {
            $lines[] = [
                'account_code' => AccAccount::AR_POS,
                'party_type' => 'pos', 'party_id' => $pos->id,
                'debit' => $baseCredit, 'credit' => 0,
            ];
        }
        $lines[] = [
            'account_code' => AccAccount::REVENUE_SALES,
            'debit' => 0, 'credit' => $baseTotal,
        ];
        if ($cost > 0) {
            $lines[] = ['account_code' => AccAccount::EXPENSES, 'debit' => $cost, 'credit' => 0];
            $lines[] = [
                'account_code' => AccAccount::INVENTORY_CARDS,
                'debit' => 0, 'credit' => $cost,
            ];
        }
        if ($baseCommission > 0 && $distributor !== null) {
            $lines[] = [
                'account_code' => AccAccount::EXPENSES,
                'debit' => $baseCommission, 'credit' => 0,
            ];
            $lines[] = [
                'account_code' => AccAccount::POS_PROFITS,
                'party_type' => 'distributor', 'party_id' => $distributor->id,
                'debit' => 0, 'credit' => $baseCommission,
            ];
        }

        return $this->posting->post('sale', [
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'doc_ref_id' => $sale->id,
            'memo' => 'بيع لنقطة ' . $pos->name . ' — ' . $sale->sale_no,
            'currency' => $currency,
            'exchange_rate' => (float) $sale->exchange_rate,
            'date' => $sale->sold_at,
            'idempotency_key' => 'sale-' . $sale->id,
            'lines' => $lines,
        ]);
    }

    private function commissionOf(?AccAgent $distributor, float $total): float
    {
        if ($distributor === null) {
            return 0.0;
        }

        return match ($distributor->commission_mode) {
            'percent' => round($total * (float) $distributor->commission_value / 100, 2),
            'fixed' => round((float) $distributor->commission_value, 2),
            default => 0.0,
        };
    }

    /** Scope a sales query to the acting distributor when needed. */
    private function salesScope(AccContext $ctx): \Closure
    {
        return function ($q) use ($ctx) {
            if ($ctx->role === 'distributor' && $ctx->agentId() !== null) {
                $id = $ctx->agentId();
                $q->where(function ($w) use ($id) {
                    $w->where('distributor_id', $id)
                        ->orWhere(function ($w2) use ($id) {
                            $w2->whereNull('distributor_id')->where('agent_id', $id);
                        });
                });
            }
        };
    }

    private function todayTotals(AccContext $ctx, ?int $distributorId): array
    {
        $sales = AccSale::where('network_owner_id', $ctx->ownerId)
            ->where('status', AccSale::STATUS_POSTED)
            ->whereDate('sold_at', Carbon::today())
            ->tap($this->salesScope($ctx))
            ->selectRaw('COUNT(*) as cnt, COALESCE(SUM(base_total),0) as total,
                         COALESCE(SUM(base_paid),0) as paid')
            ->first();

        $collections = AccCollection::where('network_owner_id', $ctx->ownerId)
            ->whereDate('collected_at', Carbon::today())
            ->when($distributorId !== null,
                fn ($q) => $q->where('collector_agent_id', $distributorId))
            ->sum('base_amount');

        return [
            'sales_count' => (int) ($sales->cnt ?? 0),
            'sales_total' => round((float) ($sales->total ?? 0), 2),
            'cash_total' => round((float) ($sales->paid ?? 0), 2),
            'credit_total' => round(
                (float) ($sales->total ?? 0) - (float) ($sales->paid ?? 0), 2
            ),
            'collections_total' => round((float) $collections, 2),
        ];
    }

    private function resolveBox(AccContext $ctx, mixed $boxId, string $currency): AccCashBox
    {
        if ($boxId !== null && $boxId !== '') {
            $box = AccCashBox::where('network_owner_id', $ctx->ownerId)
                ->where('is_active', true)
                ->lockForUpdate()
                ->find((int) $boxId);
            if ($box === null) {
                throw new AccDistException('الصندوق غير موجود أو موقوف');
            }

            return $box;
        }

        return AccCashBox::where('network_owner_id', $ctx->ownerId)
            ->where('is_default', true)
            ->where('is_active', true)
            ->lockForUpdate()
            ->first()
            ?? AccCashBox::ensureDefaultFor($ctx->ownerId, $currency);
    }

    private function nextSaleNo(int $ownerId): string
    {
        $prefix = 'SA-' . Carbon::today()->format('Ymd') . '-';
        $last = AccSale::where('network_owner_id', $ownerId)
            ->where('sale_no', 'like', $prefix . '%')
            ->lockForUpdate()
            ->max('sale_no');

        $seq = $last === null ? 1 : ((int) substr($last, -6)) + 1;

        return $prefix . str_pad((string) $seq, 6, '0', STR_PAD_LEFT);
    }

    private function addToBox(AccCashBox $box, float $delta): void
    {
        $box->balance = round((float) $box->balance + $delta, 2);
        $box->save();
    }

    private function toBase(float $amount, string $currency): float
    {
        return CurrencyService::convert($amount, $currency, self::BASE_CURRENCY);
    }

    private function rateToBase(string $currency): float
    {
        if ($currency === self::BASE_CURRENCY) {
            return 1.0;
        }
        $mult = CurrencyService::multiplierNorthToSouth();

        return $currency === 'south' && $mult > 0 ? round(1 / $mult, 6) : 1.0;
    }

    private function toBoxAmount(float $amount, string $currency, AccCashBox $box): float
    {
        return CurrencyService::convert($amount, $currency, $box->currency);
    }

    private function currency(mixed $currency): string
    {
        $c = is_string($currency) && $currency !== '' ? strtolower($currency) : self::BASE_CURRENCY;
        if (! in_array($c, ['north', 'south'], true)) {
            throw new AccDistException('عملة غير مدعومة: ' . $c);
        }

        return $c;
    }

    private function timestamp(mixed $value): Carbon
    {
        if ($value === null || $value === '') {
            return now();
        }
        if ($value instanceof \DateTimeInterface) {
            return Carbon::instance($value);
        }

        return Carbon::parse((string) $value);
    }

    private function idempotencyKey(array $data): ?string
    {
        $key = $data['idempotency_key'] ?? null;

        return is_string($key) && $key !== '' ? $key : null;
    }

    private function isUniqueViolation(QueryException $e): bool
    {
        $msg = $e->getMessage();

        return str_contains($msg, 'UNIQUE constraint failed')
            || str_contains($msg, 'Duplicate entry')
            || $e->getCode() === '23000';
    }

    private function audit(AccContext $ctx, string $action, string $entity, int $id, array $meta = []): void
    {
        AccAuditLog::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'action' => $action,
            'entity' => $entity,
            'entity_id' => $id,
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }
}
