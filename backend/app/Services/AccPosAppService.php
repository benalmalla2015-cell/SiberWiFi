<?php

namespace App\Services;

use App\Models\AccAccount;
use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\AccCardExchange;
use App\Models\AccCashBox;
use App\Models\AccCollection;
use App\Models\AccPointsLedger;
use App\Models\AccPosOrder;
use App\Models\AccPosPoint;
use App\Models\AccProfitLedger;
use App\Models\AccWithdrawal;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-07 — the POS-agent surface (PLAN §2.2 + §4: /pos/*).
 *
 * Every write is ONE atomic DB transaction:
 *
 *   requestWithdrawal()  pending request + profit hold
 *                        (ledger −amount + profit_balance down)
 *   cancelWithdrawal()   requester cancels → hold refunded
 *   decideWithdrawal()   approve | paid | reject —
 *                        paid posts a balanced `withdrawal` entry
 *                        (Dr POS_PROFITS / Cr cash box) and moves
 *                        the cash out of the drawer
 *   exchange()           instant card-for-points redemption:
 *                        points spend + stock out + `pos_sale`
 *                        journal entry, one transaction
 *
 * A pos agent is pinned to its own bound acc_pos_points row —
 * every query is tenant-scoped through AccContext.
 */
class AccPosAppService
{
    public function __construct(private AccPostingService $posting) {}

    // ── Home aggregate ───────────────────────────────────────────

    /**
     * Everything the POS home renders in one round-trip: the bound
     * point + balances, the orderable/exchangeable package catalog
     * (with live stock), headline stats, and the recent activity
     * feed (points + profit ledger merged, latest first).
     */
    public function home(AccContext $ctx): array
    {
        $pos = $this->ownPoint($ctx);

        $packages = Schema::hasTable('acc_card_categories')
            ? DB::table('acc_card_categories as c')
                ->leftJoin('acc_stock as s', function ($j) use ($ctx) {
                    $j->on('s.category_id', '=', 'c.id')
                        ->where('s.network_owner_id', '=', $ctx->ownerId);
                })
                ->where('c.network_owner_id', $ctx->ownerId)
                ->where('c.is_active', true)
                ->orderBy('c.sort_order')->orderBy('c.id')
                ->get([
                    'c.id', 'c.name', 'c.sell_price', 'c.unit_label',
                    DB::raw('COALESCE(s.qty, 0) as stock_qty'),
                ])
                ->map(fn ($c) => [
                    'id' => (int) $c->id,
                    'name' => $c->name,
                    'sell_price' => (float) $c->sell_price,
                    'unit_label' => $c->unit_label ?? 'كرت',
                    'points_cost' => (float) $c->sell_price,
                    'stock_qty' => (float) $c->stock_qty,
                    'available' => (float) $c->stock_qty > 0,
                ])
                ->values()
                ->all()
            : [];

        $ordersBase = AccPosOrder::where('network_owner_id', $ctx->ownerId)
            ->where('pos_id', $pos->id);

        $stats = [
            'pending_orders' => (clone $ordersBase)->where('status', 'pending')->count(),
            'orders_total' => (clone $ordersBase)->count(),
            'exchanges_total' => AccCardExchange::where('network_owner_id', $ctx->ownerId)
                ->where('pos_id', $pos->id)->count(),
            'pending_withdrawals' => AccWithdrawal::where('network_owner_id', $ctx->ownerId)
                ->where('requester_type', 'pos')->where('requester_id', $pos->id)
                ->whereIn('status', ['pending', 'approved'])->count(),
            'pending_withdrawals_amount' => (float) AccWithdrawal::where('network_owner_id', $ctx->ownerId)
                ->where('requester_type', 'pos')->where('requester_id', $pos->id)
                ->whereIn('status', ['pending', 'approved'])->sum('amount'),
            'collected_total' => (float) AccCollection::where('network_owner_id', $ctx->ownerId)
                ->where('party_type', 'pos')->where('party_id', $pos->id)->sum('base_amount'),
        ];

        $recentOrders = (clone $ordersBase)->with('items')->latest()->limit(5)->get()
            ->map(fn (AccPosOrder $o) => [
                'id' => $o->id,
                'order_no' => $o->order_no,
                'status' => $o->status,
                'total_amount' => (float) $o->total_amount,
                'points_total' => (float) $o->points_total,
                'items_count' => $o->items->count(),
                'created_at' => $o->created_at?->toISOString(),
            ])->values()->all();

        $recentCollections = AccCollection::where('network_owner_id', $ctx->ownerId)
            ->where('party_type', 'pos')->where('party_id', $pos->id)
            ->latest('collected_at')->limit(5)->get()
            ->map(fn (AccCollection $c) => [
                'id' => $c->id,
                'amount' => (float) $c->amount,
                'currency' => $c->currency,
                'base_amount' => (float) $c->base_amount,
                'collected_at' => $c->collected_at?->toISOString(),
                'note' => $c->note,
            ])->values()->all();

        return [
            'pos' => [
                'id' => $pos->id,
                'name' => $pos->name,
                'status' => $pos->status,
                'points_balance' => (float) $pos->points_balance,
                'profit_balance' => (float) $pos->profit_balance,
                'credit_limit' => (float) $pos->credit_limit,
                'location' => $pos->location,
                'phone' => $pos->phone,
                'owner_name' => $pos->owner_name,
            ],
            'agent' => $ctx->agent === null ? null : [
                'id' => $ctx->agent->id,
                'display_name' => $ctx->agent->display_name,
            ],
            'packages' => $packages,
            'stats' => $stats,
            'recent_orders' => $recentOrders,
            'recent_ledger' => $this->ledgerRows($ctx, $pos, 10),
            'recent_collections' => $recentCollections,
        ];
    }

    /** The recent points + profit movements of the bound point. */
    public function ledger(AccContext $ctx): array
    {
        $pos = $this->ownPoint($ctx);

        return $this->ledgerRows($ctx, $pos, 50);
    }

    // ── Withdrawals (POS request surface) ────────────────────────

    /**
     * Submit a profit withdrawal and hold the amount at once:
     * profit_ledger −amount + the POS's profit_balance moves inside
     * the same transaction — the requester cannot double-spend an
     * accrual. Replayable through idempotency_key.
     *
     * Payload: amount, receiver_name?, note?, idempotency_key?
     */
    public function requestWithdrawal(AccContext $ctx, array $data): AccWithdrawal
    {
        $key = isset($data['idempotency_key']) && $data['idempotency_key'] !== ''
            ? (string) $data['idempotency_key'] : null;
        if ($key !== null) {
            $existing = AccWithdrawal::where('idempotency_key', $key)->first();
            if ($existing) {
                return $existing;
            }
        }

        [$partyType, $partyId, $pos] = $this->resolveRequester($ctx);

        $amount = round((float) ($data['amount'] ?? 0), 2);
        if ($amount <= 0) {
            throw new AccOrderException('مبلغ السحب يجب أن يكون أكبر من صفر');
        }

        $attempts = 0;
        do {
            try {
                return DB::transaction(function () use (
                    $ctx, $data, $key, $partyType, $partyId, $pos, $amount
                ) {
                    $available = $partyType === 'pos'
                        ? (float) AccPosPoint::where('network_owner_id', $ctx->ownerId)
                            ->lockForUpdate()->find($partyId)->profit_balance
                        : $this->distributorProfit($ctx, $partyId);

                    if ($available < $amount - 0.005) {
                        throw new AccOrderException(
                            "رصيد الأرباح غير كافٍ — المتاح {$available} والمطلوب {$amount}"
                        );
                    }

                    $withdrawal = AccWithdrawal::create([
                        'network_owner_id' => $ctx->ownerId,
                        'requester_type' => $partyType,
                        'requester_id' => $partyId,
                        'requested_by' => $ctx->agentId(),
                        'amount' => $amount,
                        'status' => AccWithdrawal::STATUS_PENDING,
                        'receiver_name' => $data['receiver_name'] ?? null,
                        'note' => $data['note'] ?? null,
                        'idempotency_key' => $key,
                    ]);

                    // Take the hold: ledger delta + running balance.
                    $this->applyProfitDelta(
                        $ctx, $partyType, $partyId, $pos, -$amount,
                        'withdrawal', 'acc_withdrawals', $withdrawal->id,
                        'حجز طلب سحب #' . $withdrawal->id
                    );

                    $this->audit($ctx, 'withdrawal.request', 'acc_withdrawals', $withdrawal->id, [
                        'party' => "{$partyType}:{$partyId}",
                        'amount' => $amount,
                    ]);

                    return $withdrawal;
                });
            } catch (QueryException $e) {
                if ($key !== null) {
                    $existing = AccWithdrawal::where('idempotency_key', $key)->first();
                    if ($existing) {
                        return $existing;
                    }
                }
                if (++$attempts >= 3 || ! $this->isUniqueViolation($e)) {
                    throw $e;
                }
            }
        } while (true);
    }

    /** The caller's own withdrawal requests, latest first. */
    public function myWithdrawals(AccContext $ctx)
    {
        [$partyType, $partyId] = $this->resolveRequester($ctx);

        return AccWithdrawal::where('network_owner_id', $ctx->ownerId)
            ->where('requester_type', $partyType)
            ->where('requester_id', $partyId)
            ->latest()
            ->paginate(25);
    }

    /**
     * The requester cancels a still-pending request — the hold is
     * refunded in the same transaction. Replayable.
     */
    public function cancelWithdrawal(AccContext $ctx, int $id): AccWithdrawal
    {
        [$partyType, $partyId] = $this->resolveRequester($ctx);

        return DB::transaction(function () use ($ctx, $partyType, $partyId, $id) {
            $w = AccWithdrawal::where('network_owner_id', $ctx->ownerId)
                ->where('requester_type', $partyType)
                ->where('requester_id', $partyId)
                ->lockForUpdate()
                ->find($id);

            if ($w === null) {
                throw new AccOrderException('طلب السحب غير موجود', 404);
            }
            if ($w->status === AccWithdrawal::STATUS_CANCELLED) {
                return $w;
            }
            if ($w->status !== AccWithdrawal::STATUS_PENDING) {
                throw new AccOrderException('لا يمكن إلغاء طلب تمت مراجعته', 409);
            }

            $w->status = AccWithdrawal::STATUS_CANCELLED;
            $w->save();

            $this->refundHold($ctx, $w);

            $this->audit($ctx, 'withdrawal.cancel', 'acc_withdrawals', $w->id, [
                'amount' => (float) $w->amount,
            ]);

            return $w;
        });
    }

    // ── Withdrawals (management decide surface) ──────────────────

    /**
     * Decide a withdrawal: `approve` flags it for payout, `paid`
     * settles it in cash (balanced withdrawal entry + box outflow),
     * `reject` refunds the held profit. All replayable; decided
     * states never regress (paid is terminal).
     *
     * Payload for paid: cash_box_id?, receiver_name?, receipt_no?,
     *                   review_note?
     */
    public function decideWithdrawal(AccContext $ctx, int $id, string $action, array $data = []): AccWithdrawal
    {
        return DB::transaction(function () use ($ctx, $id, $action, $data) {
            $w = AccWithdrawal::where('network_owner_id', $ctx->ownerId)
                ->lockForUpdate()
                ->find($id);
            if ($w === null) {
                throw new AccOrderException('طلب السحب غير موجود', 404);
            }

            switch ($action) {
                case 'approve':
                    if ($w->status === AccWithdrawal::STATUS_APPROVED) {
                        return $w;
                    }
                    if ($w->status !== AccWithdrawal::STATUS_PENDING) {
                        throw new AccOrderException('لا يمكن اعتماد طلب في حالته الحالية', 409);
                    }
                    $w->status = AccWithdrawal::STATUS_APPROVED;
                    $this->stampReview($ctx, $w, $data);
                    break;

                case 'reject':
                    if ($w->status === AccWithdrawal::STATUS_REJECTED) {
                        return $w;
                    }
                    if (! in_array($w->status, [AccWithdrawal::STATUS_PENDING, AccWithdrawal::STATUS_APPROVED], true)) {
                        throw new AccOrderException('لا يمكن رفض طلب في حالته الحالية', 409);
                    }
                    $w->status = AccWithdrawal::STATUS_REJECTED;
                    $this->stampReview($ctx, $w, $data);
                    $this->refundHold($ctx, $w);
                    break;

                case 'paid':
                    if ($w->status === AccWithdrawal::STATUS_PAID) {
                        return $w;
                    }
                    if (! in_array($w->status, [AccWithdrawal::STATUS_PENDING, AccWithdrawal::STATUS_APPROVED], true)) {
                        throw new AccOrderException('لا يمكن صرف طلب في حالته الحالية', 409);
                    }
                    $this->payWithdrawal($ctx, $w, $data);
                    break;

                default:
                    throw new AccOrderException('إجراء غير معروف: ' . $action);
            }

            $w->save();

            $this->audit($ctx, 'withdrawal.' . $action, 'acc_withdrawals', $w->id, [
                'amount' => (float) $w->amount,
                'party' => "{$w->requester_type}:{$w->requester_id}",
            ]);

            return $w;
        });
    }

    // ── Card exchange (instant points → cards) ───────────────────

    /**
     * Redeem points for cards instantly — the direct counterpart of
     * the approval-gated pos order. ONE transaction: exchange row +
     * points spend + stock out + balanced `pos_sale` journal entry.
     * points_spent is server-priced (qty × sell_price): one point
     * buys one base-currency unit of card value.
     *
     * Payload: category_id, qty, note?, idempotency_key?
     */
    public function exchange(AccContext $ctx, array $data): AccCardExchange
    {
        $key = isset($data['idempotency_key']) && $data['idempotency_key'] !== ''
            ? (string) $data['idempotency_key'] : null;
        if ($key !== null) {
            $existing = AccCardExchange::where('idempotency_key', $key)->first();
            if ($existing) {
                return $existing;
            }
        }

        $pos = $this->ownPoint($ctx);

        $categoryId = (int) ($data['category_id'] ?? 0);
        $qty = (int) ($data['qty'] ?? 0);
        if ($qty < 1) {
            throw new AccOrderException('الكمية يجب أن تكون 1 فأكثر');
        }

        $category = DB::table('acc_card_categories')
            ->where('network_owner_id', $ctx->ownerId)
            ->where('is_active', true)
            ->find($categoryId);
        if ($category === null) {
            throw new AccOrderException('فئة الكروت غير موجودة أو موقوفة');
        }

        $pointsSpent = round($qty * (float) $category->sell_price, 2);
        if ($pointsSpent <= 0) {
            throw new AccOrderException('قيمة الاستبدال صفر — راجع سعر الفئة');
        }

        $attempts = 0;
        do {
            try {
                return DB::transaction(function () use (
                    $ctx, $data, $key, $pos, $category, $qty, $pointsSpent
                ) {
                    $point = AccPosPoint::where('network_owner_id', $ctx->ownerId)
                        ->lockForUpdate()->find($pos->id);
                    if ((float) $point->points_balance < $pointsSpent - 0.005) {
                        throw new AccOrderException(
                            "رصيد النقاط غير كافٍ — المطلوب {$pointsSpent} والمتاح {$point->points_balance}"
                        );
                    }

                    // Stock out — the exchange never draws below zero.
                    $stock = DB::table('acc_stock')
                        ->where('network_owner_id', $ctx->ownerId)
                        ->where('category_id', $category->id)
                        ->lockForUpdate()
                        ->first();
                    $available = (float) ($stock->qty ?? 0);
                    if ($stock === null || $available < $qty) {
                        throw new AccOrderException(
                            "مخزون غير كافٍ لـ «{$category->name}» — المتاح {$available} والمطلوب {$qty}"
                        );
                    }

                    $exchange = AccCardExchange::create([
                        'network_owner_id' => $ctx->ownerId,
                        'pos_id' => $point->id,
                        'category_id' => (int) $category->id,
                        'category_name' => $category->name,
                        'qty' => $qty,
                        'unit_price' => (float) $category->sell_price,
                        'points_spent' => $pointsSpent,
                        'status' => AccCardExchange::STATUS_COMPLETED,
                        'agent_id' => $ctx->agentId(),
                        'note' => $data['note'] ?? null,
                        'idempotency_key' => $key,
                    ]);

                    DB::table('acc_stock')
                        ->where('id', $stock->id)
                        ->update(['qty' => $available - $qty, 'updated_at' => now()]);

                    DB::table('acc_stock_movements')->insert([
                        'network_owner_id' => $ctx->ownerId,
                        'category_id' => (int) $category->id,
                        'type' => 'exchange',
                        'qty' => -$qty, // signed: negative = out
                        'unit_cost' => (float) ($stock->avg_cost ?: $category->cost_price),
                        'ref_type' => 'acc_card_exchanges',
                        'ref_id' => $exchange->id,
                        'agent_id' => $ctx->agentId(),
                        'note' => 'استبدال نقاط #' . $exchange->id,
                        'created_at' => now(),
                    ]);

                    $point->points_balance = round((float) $point->points_balance - $pointsSpent, 2);
                    $point->save();

                    AccPointsLedger::create([
                        'network_owner_id' => $ctx->ownerId,
                        'pos_id' => $point->id,
                        'reason' => 'conversion',
                        'delta' => -$pointsSpent,
                        'ref_type' => 'acc_card_exchanges',
                        'ref_id' => $exchange->id,
                        'agent_id' => $ctx->agentId(),
                        'balance_after' => (float) $point->points_balance,
                        'note' => "استبدال {$qty} × {$category->name}",
                        'created_at' => now(),
                    ]);

                    $cost = round($qty * (float) ($stock->avg_cost ?: $category->cost_price), 2);
                    $lines = [
                        $this->leg(AccAccount::CUSTOMER_BALANCES, 'pos', $point->id, $pointsSpent, 0),
                        $this->leg(AccAccount::REVENUE_SALES, null, null, 0, $pointsSpent),
                    ];
                    if ($cost > 0) {
                        $lines[] = $this->leg(AccAccount::EXPENSES, null, null, $cost, 0);
                        $lines[] = $this->leg(AccAccount::INVENTORY_CARDS, null, null, 0, $cost);
                    }

                    $entry = $this->posting->post('pos_sale', [
                        'network_owner_id' => $ctx->ownerId,
                        'agent_id' => $ctx->agentId(),
                        'doc_ref_id' => $exchange->id,
                        'memo' => "استبدال نقاط: {$qty} × {$category->name} لـ «{$point->name}»",
                        'idempotency_key' => 'exchange-' . $exchange->id,
                        'lines' => $lines,
                    ]);

                    $exchange->journal_entry_id = $entry->id;
                    $exchange->save();

                    $this->audit($ctx, 'exchange.create', 'acc_card_exchanges', $exchange->id, [
                        'pos' => $point->id,
                        'category' => (int) $category->id,
                        'qty' => $qty,
                        'points' => $pointsSpent,
                    ]);

                    return $exchange;
                });
            } catch (QueryException $e) {
                if ($key !== null) {
                    $existing = AccCardExchange::where('idempotency_key', $key)->first();
                    if ($existing) {
                        return $existing;
                    }
                }
                if (++$attempts >= 3 || ! $this->isUniqueViolation($e)) {
                    throw $e;
                }
            }
        } while (true);
    }

    /** The bound point's exchange history, latest first. */
    public function myExchanges(AccContext $ctx)
    {
        $pos = $this->ownPoint($ctx);

        return AccCardExchange::where('network_owner_id', $ctx->ownerId)
            ->where('pos_id', $pos->id)
            ->latest()
            ->paginate(25);
    }

    // ── Internals ────────────────────────────────────────────────

    /** The POS point bound to this pos agent — 403 when none. */
    private function ownPoint(AccContext $ctx): AccPosPoint
    {
        $agentId = $ctx->agentId();
        $pos = $agentId === null ? null : AccPosPoint::where('network_owner_id', $ctx->ownerId)
            ->where('agent_id', $agentId)
            ->where('status', AccPosPoint::STATUS_ACTIVE)
            ->first();

        if ($pos === null) {
            throw new AccOrderException('لا توجد نقطة بيع نشطة مرتبطة بحسابك', 403);
        }

        return $pos;
    }

    /**
     * Who the withdrawal is for: a pos agent → its bound point
     * (returns the AccPosPoint too), a distributor agent → its own
     * acc_agents row. Owner/admin request on behalf is rejected —
     * management only decides.
     */
    private function resolveRequester(AccContext $ctx): array
    {
        $agent = $ctx->agent;
        if ($agent !== null && $agent->role === 'pos') {
            $pos = $this->ownPoint($ctx);

            return ['pos', $pos->id, $pos];
        }
        if ($agent !== null && $agent->role === 'distributor') {
            return ['distributor', $agent->id, null];
        }

        throw new AccOrderException('هذا الحساب لا يملك رصيد أرباح قابلاً للسحب', 403);
    }

    /** A distributor's live profit (no balance column — the ledger is truth). */
    private function distributorProfit(AccContext $ctx, int $agentId): float
    {
        $q = AccProfitLedger::where('network_owner_id', $ctx->ownerId)
            ->where('party_type', 'distributor')
            ->where('party_id', $agentId);

        return (float) $q->sum('delta');
    }

    /**
     * Write a signed profit delta and keep the running balance in
     * sync: pos parties roll into acc_pos_points.profit_balance,
     * distributor parties live in the ledger only.
     */
    private function applyProfitDelta(
        AccContext $ctx,
        string $partyType,
        int $partyId,
        ?AccPosPoint $pos,
        float $delta,
        string $reason,
        string $refType,
        int $refId,
        string $note
    ): void {
        if ($partyType === 'pos' && $pos !== null) {
            $pos->profit_balance = round((float) $pos->profit_balance + $delta, 2);
            $pos->save();
        }

        AccProfitLedger::create([
            'network_owner_id' => $ctx->ownerId,
            'party_type' => $partyType,
            'party_id' => $partyId,
            'reason' => $reason,
            'delta' => $delta,
            'ref_type' => $refType,
            'ref_id' => $refId,
            'agent_id' => $ctx->agentId(),
            'note' => $note,
            'created_at' => now(),
        ]);
    }

    /** Refund a held withdrawal amount back to the profit balance. */
    private function refundHold(AccContext $ctx, AccWithdrawal $w): void
    {
        $pos = $w->requester_type === 'pos'
            ? AccPosPoint::where('network_owner_id', $ctx->ownerId)
                ->lockForUpdate()->find($w->requester_id)
            : null;

        $this->applyProfitDelta(
            $ctx, $w->requester_type, (int) $w->requester_id, $pos,
            (float) $w->amount, 'withdrawal', 'acc_withdrawals', $w->id,
            'استرداد حجز طلب سحب #' . $w->id
        );
    }

    private function stampReview(AccContext $ctx, AccWithdrawal $w, array $data): void
    {
        $w->reviewed_by = $ctx->user->id;
        $w->reviewed_at = now();
        if (array_key_exists('review_note', $data) || array_key_exists('reason', $data)) {
            $w->review_note = $data['review_note'] ?? $data['reason'] ?? null;
        }
    }

    /**
     * Pay out an approved/pending request: balanced withdrawal
     * entry (Dr POS_PROFITS liability / Cr cash box) + box outflow,
     * atomically. The hold taken at request time is what the entry
     * settles — no further ledger delta here.
     */
    private function payWithdrawal(AccContext $ctx, AccWithdrawal $w, array $data): void
    {
        $amount = (float) $w->amount;

        $box = isset($data['cash_box_id']) && $data['cash_box_id'] !== ''
            ? AccCashBox::where('network_owner_id', $ctx->ownerId)
                ->where('is_active', true)->lockForUpdate()->find((int) $data['cash_box_id'])
            : AccCashBox::ensureDefaultFor($ctx->ownerId);
        if ($box === null) {
            throw new AccOrderException('الصندوق غير موجود أو موقوف');
        }
        if ((float) $box->balance < $amount - 0.005) {
            throw new AccOrderException(
                "رصيد «{$box->name}» غير كافٍ للصرف — المتاح {$box->balance} والمطلوب {$amount}"
            );
        }

        $partyLabel = $w->requester_type === 'pos'
            ? (AccPosPoint::find($w->requester_id)?->name ?? 'نقطة بيع')
            : (AccAgent::find($w->requester_id)?->display_name ?? 'موزع');

        $entry = $this->posting->post('withdrawal', [
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'doc_ref_id' => $w->id,
            'memo' => 'صرف أرباح لـ ' . $partyLabel . ' — طلب #' . $w->id,
            'idempotency_key' => 'withdrawal-' . $w->id . '-paid',
            'lines' => [
                $this->leg(AccAccount::POS_PROFITS, $w->requester_type, (int) $w->requester_id, $amount, 0),
                $this->leg(AccAccount::CASH_MAIN, 'box', $box->id, 0, $amount),
            ],
        ]);

        $box->balance = round((float) $box->balance - $amount, 2);
        $box->save();

        $w->status = AccWithdrawal::STATUS_PAID;
        $w->cash_box_id = $box->id;
        $w->journal_entry_id = $entry->id;
        $w->paid_at = now();
        $this->stampReview($ctx, $w, $data);
        if (isset($data['receiver_name'])) {
            $w->receiver_name = $data['receiver_name'];
        }
        if (isset($data['receipt_no'])) {
            $w->receipt_no = $data['receipt_no'];
        }
    }

    /** Points + profit movements merged latest-first for the feed. */
    private function ledgerRows(AccContext $ctx, AccPosPoint $pos, int $limit): array
    {
        $points = AccPointsLedger::where('network_owner_id', $ctx->ownerId)
            ->where('pos_id', $pos->id)->latest('id')->limit($limit)->get()
            ->map(fn (AccPointsLedger $r) => [
                'kind' => 'points',
                'reason' => $r->reason,
                'delta' => (float) $r->delta,
                'balance_after' => $r->balance_after !== null ? (float) $r->balance_after : null,
                'note' => $r->note,
                'created_at' => $r->created_at?->toISOString(),
            ]);

        $profit = AccProfitLedger::where('network_owner_id', $ctx->ownerId)
            ->where('party_type', 'pos')->where('party_id', $pos->id)
            ->latest('id')->limit($limit)->get()
            ->map(fn (AccProfitLedger $r) => [
                'kind' => 'profit',
                'reason' => $r->reason,
                'delta' => (float) $r->delta,
                'balance_after' => null,
                'note' => $r->note,
                'created_at' => $r->created_at?->toISOString(),
            ]);

        return $points->concat($profit)
            ->sortByDesc('created_at')
            ->take($limit)
            ->values()
            ->all();
    }

    private function leg(string $account, ?string $partyType, ?int $partyId, float $debit, float $credit): array
    {
        return [
            'account_code' => $account,
            'party_type' => $partyType,
            'party_id' => $partyId,
            'debit' => $debit,
            'credit' => $credit,
        ];
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
