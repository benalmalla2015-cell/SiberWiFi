<?php

namespace App\Services;

use App\Models\AccAuditLog;
use App\Models\AccJournalEntry;
use App\Models\AccPostingMap;
use App\Models\AccStock;
use App\Models\AccStockMovement;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-08 — platform customer-app sale posting (PLAN §2.6 + §3).
 *
 * sync() scans `transactions` (status=completed, non-advance) on the
 * owner's networks and turns each paid card sale into:
 *   - a `card_purchase_platform` journal entry:
 *       Dr cash_account        (owner's net  = native − commission)
 *       Dr commission_account  (platform fee)
 *         Cr revenue_account   (native sale price)
 *       + COGS legs when the sold cards carry a stock cost
 *         (Dr cogs_account / Cr inventory_account)
 *   - a `sale` stock movement per sold card, so acc_stock mirrors
 *     physical availability.
 *
 * ISOLATION CONTRACT (§0.3) — enforced, not just documented:
 *   everything below runs inside AccPlatformReadOnly::run(); any
 *   insert/update/delete/DDL touching transactions/transaction_cards/
 *   cards/card_categories/wallet_logs/networks/users/wallets throws
 *   inside the guarded section and the sale's transaction rolls back.
 *
 * Idempotency: journal `idempotency_key` = platform-sale-{tx.id} and
 * the stock movements' (ref_type, ref_id, type) unique index make the
 * sync freely replayable. Card-level refs ('card', card.id) match the
 * router-card sync's signature, so a MikroTik card sold via the app is
 * never double-counted whichever path posts it first.
 */
class AccPlatformSalesService
{
    /** Journal base denomination — same convention as AccMoneyService. */
    private const BASE_CURRENCY = 'north';

    public function __construct(
        private AccPostingService $posting,
        private AccStockService $stock,
    ) {}

    /**
     * Scan platform transactions and post the missing ones.
     *
     * @return array{scanned:int,posted:int,skipped:int,movements:int,errors:list<array>}
     */
    public function sync(AccContext $ctx, int $limit = 200): array
    {
        return AccPlatformReadOnly::run(function () use ($ctx, $limit) {
            $stats = [
                'scanned' => 0, 'posted' => 0, 'skipped' => 0,
                'movements' => 0, 'errors' => [],
            ];

            if (! Schema::hasTable('transactions') || ! Schema::hasTable('networks')) {
                return $stats;
            }

            $networkIds = DB::table('networks')
                ->where('user_id', $ctx->ownerId)
                ->pluck('id');
            if ($networkIds->isEmpty()) {
                return $stats;
            }

            $query = DB::table('transactions')
                ->whereIn('network_id', $networkIds)
                ->where('status', 'completed');
            if (Schema::hasColumn('transactions', 'is_advance')) {
                // "سلفني" hand-outs are a debt flow, not a paid sale —
                // the owner's profit is only realized on repayment.
                $query->where('is_advance', 0);
            }

            $rows = $query->orderBy('id')->limit(max(1, min(500, $limit)))->get([
                'id', 'transaction_number', 'user_id', 'network_id', 'card_id',
                'category_id', 'quantity', 'unit_price', 'total_amount',
                'commission_amount', 'network_owner_amount',
                'native_amount', 'network_currency', 'created_at',
            ]);
            $stats['scanned'] = $rows->count();
            if ($rows->isEmpty()) {
                return $stats;
            }

            $postedIds = AccJournalEntry::where('network_owner_id', $ctx->ownerId)
                ->where('doc_type', 'card_purchase_platform')
                ->whereIn('doc_ref_id', $rows->pluck('id')->all())
                ->pluck('doc_ref_id')
                ->flip();

            $map = AccPostingMap::accountsFor(
                $ctx->ownerId, AccPostingMap::SOURCE_CARD_PURCHASE
            );

            foreach ($rows as $tx) {
                if ($postedIds->has($tx->id)) {
                    $stats['skipped']++;
                    continue;
                }
                try {
                    $stats['movements'] += DB::transaction(
                        fn () => $this->postOne($ctx, $tx, $map)
                    );
                    $stats['posted']++;
                } catch (\Throwable $e) {
                    // One bad row never blocks the backlog — it is
                    // reported and re-attempted on the next run.
                    $stats['errors'][] = [
                        'transaction_id' => $tx->id,
                        'error' => $e->getMessage(),
                    ];
                }
            }

            if ($stats['posted'] > 0) {
                AccAuditLog::create([
                    'network_owner_id' => $ctx->ownerId,
                    'agent_id' => $ctx->agentId(),
                    'action' => 'platform_sales.sync',
                    'entity' => 'transactions',
                    'entity_id' => 0,
                    'meta' => $stats,
                    'created_at' => now(),
                ]);
            }

            return $stats;
        });
    }

    /**
     * One sale → stock movements + balanced entry, inside the caller's
     * DB::transaction. Returns the number of movements written.
     */
    private function postOne(AccContext $ctx, object $tx, array $map): int
    {
        $cards = $this->cardsFor($tx);
        $moves = 0;
        $cats = [];

        // ── Stock: each sold card enters then leaves exactly once.
        // The 'in' covers platform-source cards that never passed
        // through the router sync; it is a no-op for pre-synced ones.
        foreach ($cards as $card) {
            $catId = $cats[$card->category_id]
                ??= $this->stock
                    ->accCategoryForPlatform($ctx->ownerId, (int) $card->category_id, 'platform')
                    ->id;

            if (! $this->moved($ctx->ownerId, 'card', (int) $card->id, 'in')) {
                $this->stock->move(
                    $ctx->ownerId, $catId, 'in', 1, null,
                    'card', (int) $card->id, $ctx->agentId(),
                    'كرت منصة — مبيعات التطبيق'
                );
                $moves++;
            }
            if (! $this->moved($ctx->ownerId, 'card', (int) $card->id, 'sale')
                && ! $this->moved($ctx->ownerId, 'card', (int) $card->id, 'out')) {
                $this->stock->move(
                    $ctx->ownerId, $catId, 'sale', -1, null,
                    'card', (int) $card->id, $ctx->agentId(),
                    'بيع عبر تطبيق العميل ' . ($tx->transaction_number ?? '')
                );
                $moves++;
            }
        }

        // Sold cards without a cards-row link still consume stock.
        $remainder = max(0, (int) $tx->quantity - count($cards));
        if ($remainder > 0) {
            $catId = $cats[(int) $tx->category_id]
                ??= $this->stock
                    ->accCategoryForPlatform($ctx->ownerId, (int) $tx->category_id, 'platform')
                    ->id;
            if (! $this->moved($ctx->ownerId, 'platform_transaction', (int) $tx->id, 'in')) {
                $this->stock->move(
                    $ctx->ownerId, $catId, 'in', $remainder, null,
                    'platform_transaction', (int) $tx->id, $ctx->agentId(),
                    'كروت منصة — قيد شراء ' . ($tx->transaction_number ?? '')
                );
                $moves++;
            }
            if (! $this->moved($ctx->ownerId, 'platform_transaction', (int) $tx->id, 'sale')) {
                $this->stock->move(
                    $ctx->ownerId, $catId, 'sale', -$remainder, null,
                    'platform_transaction', (int) $tx->id, $ctx->agentId(),
                    'بيع عبر تطبيق العميل ' . ($tx->transaction_number ?? '')
                );
                $moves++;
            }
        }

        // ── Journal: net proceeds + platform fee = gross revenue.
        $currency = in_array($tx->network_currency ?? null, ['north', 'south'], true)
            ? $tx->network_currency
            : self::BASE_CURRENCY;
        $native = (float) ($tx->native_amount ?? 0);
        if ($native <= 0) {
            $native = (float) ($tx->total_amount ?? 0);
        }
        if ($native <= 0) {
            $native = round((float) ($tx->unit_price ?? 0) * (int) $tx->quantity, 2);
        }
        $commission = max(0.0, (float) ($tx->commission_amount ?? 0));

        $revenue = $this->toBase($native, $currency);
        $fee = $this->toBase($commission, $currency);
        // net derived (not converted) → debit side balances revenue exactly.
        $net = round($revenue - $fee, 2);

        $cost = $this->soldCost($ctx->ownerId, $tx, $cards);

        $lines = [];
        if ($net > 0) {
            $lines[] = ['account_code' => $map['cash_account'],
                        'debit' => $net, 'credit' => 0];
        }
        if ($fee > 0) {
            $lines[] = ['account_code' => $map['commission_account'],
                        'debit' => $fee, 'credit' => 0];
        }
        if ($revenue > 0) {
            $lines[] = ['account_code' => $map['revenue_account'],
                        'debit' => 0, 'credit' => $revenue];
        }
        if ($cost > 0) {
            $lines[] = ['account_code' => $map['cogs_account'],
                        'debit' => $cost, 'credit' => 0];
            $lines[] = ['account_code' => $map['inventory_account'],
                        'debit' => 0, 'credit' => $cost];
        }

        if (count($lines) >= 2) {
            $this->posting->post('card_purchase_platform', [
                'network_owner_id' => $ctx->ownerId,
                'agent_id' => $ctx->agentId(),
                'doc_ref_id' => (int) $tx->id,
                'date' => $tx->created_at,
                'currency' => $currency,
                'exchange_rate' => $this->rateToBase($currency),
                'memo' => 'بيع كرت عبر تطبيق العميل '
                    . ($tx->transaction_number ?? ('#' . $tx->id)),
                'idempotency_key' => 'platform-sale-' . $tx->id,
                'lines' => $lines,
            ]);
        }

        return $moves;
    }

    /**
     * Sold cards linked to the transaction — via transaction_cards
     * first, falling back to the header card_id. READ-ONLY.
     *
     * @return list<object>
     */
    private function cardsFor(object $tx): array
    {
        $ids = [];
        if (Schema::hasTable('transaction_cards')) {
            $ids = DB::table('transaction_cards')
                ->where('transaction_id', $tx->id)
                ->pluck('card_id')
                ->all();
        }
        if ($ids === [] && ! empty($tx->card_id)) {
            $ids = [$tx->card_id];
        }
        if ($ids === [] || ! Schema::hasTable('cards')) {
            return [];
        }

        return DB::table('cards')
            ->whereIn('id', array_unique(array_map('intval', $ids)))
            ->get(['id', 'category_id'])
            ->all();
    }

    private function moved(int $ownerId, string $refType, int $refId, string $type): bool
    {
        return AccStockMovement::where('network_owner_id', $ownerId)
            ->where('ref_type', $refType)
            ->where('ref_id', $refId)
            ->where('type', $type)
            ->exists();
    }

    /**
     * Cost of goods for the COGS legs — the unit_cost stamped on the
     * sale/out movements for this transaction's cards (base units,
     * same convention as pos_sale).
     */
    private function soldCost(int $ownerId, object $tx, array $cards): float
    {
        $cost = 0.0;
        $cardIds = array_map(fn ($c) => (int) $c->id, $cards);
        if ($cardIds !== []) {
            $cost += (float) AccStockMovement::where('network_owner_id', $ownerId)
                ->where('ref_type', 'card')
                ->whereIn('ref_id', $cardIds)
                ->whereIn('type', ['sale', 'out'])
                ->sum('unit_cost');
        }
        $remainder = AccStockMovement::where('network_owner_id', $ownerId)
            ->where('ref_type', 'platform_transaction')
            ->where('ref_id', (int) $tx->id)
            ->where('type', 'sale')
            ->first();
        if ($remainder !== null) {
            $cost += (float) $remainder->unit_cost * abs((float) $remainder->qty);
        }

        return round($cost, 2);
    }

    /** Document amount → journal base (north) via the platform rate. */
    private function toBase(float $amount, string $currency): float
    {
        return CurrencyService::convert($amount, $currency, self::BASE_CURRENCY);
    }

    /** The rate that turns 1 unit of `$currency` into base units. */
    private function rateToBase(string $currency): float
    {
        if ($currency === self::BASE_CURRENCY) {
            return 1.0;
        }
        $mult = CurrencyService::multiplierNorthToSouth();

        return $currency === 'south' && $mult > 0 ? round(1 / $mult, 6) : 1.0;
    }

    /** Exposed for the controller's listings — avg stock cost helper. */
    public function avgCost(int $ownerId, int $accCategoryId): float
    {
        return (float) (AccStock::where('network_owner_id', $ownerId)
            ->where('category_id', $accCategoryId)
            ->value('avg_cost') ?? 0);
    }
}
