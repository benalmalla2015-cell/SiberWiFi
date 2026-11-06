<?php

namespace App\Services;

use App\Models\AccAccount;
use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\AccCommission;
use App\Models\AccPointsLedger;
use App\Models\AccPosOrder;
use App\Models\AccPosPoint;
use App\Models\AccProfitLedger;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-04 — the POS order document cycle (PLAN §2.2 + §3).
 *
 * create(): pending order + items + order_no, replayable through
 *   idempotency_key.
 * approve(): ONE atomic DB transaction —
 *   1) status flip pending→approved (row lock)
 *   2) stock out per item (acc_stock + acc_stock_movements,
 *      forward-compatible hook — activates when ACC-02 lands)
 *   3) acc_points_ledger spend + acc_pos_points.points_balance
 *   4) acc_profit_ledger distributor commission
 *   5) balanced pos_sale journal entry via AccPostingService
 *      (nested savepoint — rolls back with the outer transaction)
 *   6) acc_audit_log
 *   Any failure (insufficient points/stock, unbalanced entry)
 *   rolls the whole thing back — nothing half-posts.
 * reject(): status flip + audit, no ledger effects.
 *
 * Both decide paths are replayable: an already-approved approve
 * call returns the order as-is instead of double-posting.
 */
class AccPosOrderService
{
    public function __construct(
        private AccPostingService $posting,
        private AccDiscountService $discounts,
        private AccTierRewardWriter $tierRewards,
    ) {}

    // ── Create (POS request) ─────────────────────────────────────

    /**
     * Payload: pos_id, items[{category_id?, name?, qty, unit_price?,
     * unit_cost?}], points_total?, distributor_id?, note?,
     * idempotency_key?
     */
    public function create(AccContext $ctx, array $data): AccPosOrder
    {
        $pos = $this->resolvePos($ctx, (int) ($data['pos_id'] ?? 0));
        $items = $this->resolveItems($ctx->ownerId, $data['items'] ?? []);
        $pointsTotal = round((float) ($data['points_total'] ?? 0), 2);
        if ($pointsTotal < 0) {
            throw new AccOrderException('إجمالي النقاط لا يمكن أن يكون سالباً');
        }

        $distributorId = null;
        if (! empty($data['distributor_id'])) {
            $distributorId = (int) $data['distributor_id'];
            $ok = AccAgent::where('network_owner_id', $ctx->ownerId)
                ->where('id', $distributorId)
                ->where('role', 'distributor')
                ->where('status', AccAgent::STATUS_ACTIVE)
                ->exists();
            if (! $ok) {
                throw new AccOrderException('الموزع المحدد غير صالح');
            }
        }

        $key = isset($data['idempotency_key']) && $data['idempotency_key'] !== ''
            ? (string) $data['idempotency_key'] : null;

        if ($key !== null) {
            $existing = AccPosOrder::where('idempotency_key', $key)->first();
            if ($existing) {
                return $existing->load('items');
            }
        }

        $total = round(array_sum(array_column($items, 'line_total')), 2);
        $attempts = 0;

        do {
            try {
                return DB::transaction(function () use (
                    $ctx, $pos, $items, $pointsTotal, $distributorId, $key, $total, $data
                ) {
                    $order = AccPosOrder::create([
                        'network_owner_id' => $ctx->ownerId,
                        'order_no' => $this->nextOrderNo($ctx->ownerId),
                        'pos_id' => $pos->id,
                        'distributor_id' => $distributorId,
                        'requested_by' => $ctx->agentId(),
                        'status' => AccPosOrder::STATUS_PENDING,
                        'total_amount' => $total,
                        'points_total' => $pointsTotal,
                        'note' => $data['note'] ?? null,
                        'idempotency_key' => $key,
                    ]);

                    foreach ($items as $item) {
                        $order->items()->create($item);
                    }

                    $this->audit($ctx, 'pos_order.create', $order->id, [
                        'order_no' => $order->order_no,
                        'items' => count($items),
                        'total' => $total,
                        'points' => $pointsTotal,
                    ]);

                    return $order->load('items');
                });
            } catch (QueryException $e) {
                if ($key !== null) {
                    $existing = AccPosOrder::where('idempotency_key', $key)->first();
                    if ($existing) {
                        return $existing->load('items');
                    }
                }
                if (++$attempts >= 3 || ! $this->isUniqueViolation($e)) {
                    throw $e;
                }
                // order_no race — retry with a fresh sequence lookup.
            }
        } while (true);
    }

    // ── Approve (the atomic cycle) ───────────────────────────────

    public function approve(AccContext $ctx, int $orderId): AccPosOrder
    {
        return DB::transaction(function () use ($ctx, $orderId) {
            $order = AccPosOrder::where('network_owner_id', $ctx->ownerId)
                ->lockForUpdate()
                ->find($orderId);

            if ($order === null) {
                throw new AccOrderException('الطلب غير موجود', 404);
            }
            // Replayable: re-approving returns the decided order.
            if ($order->status === AccPosOrder::STATUS_APPROVED) {
                return $order->load('items');
            }
            if ($order->status === AccPosOrder::STATUS_REJECTED) {
                throw new AccOrderException('لا يمكن اعتماد طلب مرفوض', 409);
            }

            $pos = AccPosPoint::where('network_owner_id', $ctx->ownerId)
                ->lockForUpdate()
                ->find($order->pos_id);
            if ($pos === null) {
                throw new AccOrderException('نقطة البيع لم تعد موجودة');
            }

            $items = $order->items()->get();

            // 1) Stock out (ACC-02 hook — activates when its tables land).
            $this->applyStockOut($ctx, $order, $items);

            // ACC-10 — tier rewards on the gross document value: a
            // direct_percent tier discounts the posted value, the POS
            // prepays never more than the discounted value, and
            // points/profit/commission bonuses apply below — all in
            // this same transaction.
            $grossPoints = (float) $order->points_total;
            $docValue = (float) $order->total_amount > 0
                ? (float) $order->total_amount : $grossPoints;
            $rewards = $this->discounts->rewards(
                $ctx->ownerId,
                (float) $items->sum(fn ($i) => (int) $i->qty),
                $docValue
            );
            $netValue = round(max(0.0, $docValue - $rewards['discount']), 2);

            // 2) Points spend — capped at the discounted value.
            $pointsTotal = min($grossPoints, $netValue);
            if ($pointsTotal > 0) {
                if ((float) $pos->points_balance < $pointsTotal) {
                    throw new AccOrderException(
                        "رصيد نقاط غير كافٍ — المطلوب {$pointsTotal} والمتاح {$pos->points_balance}"
                    );
                }
                $pos->points_balance = (float) $pos->points_balance - $pointsTotal;
                $pos->save();

                AccPointsLedger::create([
                    'network_owner_id' => $ctx->ownerId,
                    'pos_id' => $pos->id,
                    'reason' => 'order_purchase',
                    'delta' => -$pointsTotal,
                    'ref_type' => 'acc_pos_orders',
                    'ref_id' => $order->id,
                    'agent_id' => $ctx->agentId(),
                    'balance_after' => (float) $pos->points_balance,
                    'note' => 'طلب ' . $order->order_no,
                    'created_at' => now(),
                ]);
            }

            // ACC-10 — points/profit tier bonuses credit the POS.
            $this->tierRewards->credit(
                $ctx, $pos, 'acc_pos_orders', $order->id,
                $order->order_no, $rewards
            );

            // 3) Distributor commission → profit ledger (+ journal leg)
            //    and the ACC-06 monthly accrual (forward-compatible
            //    hook — activates when acc_commissions exists).
            //    A commission tier stacks on the agent's own rate.
            $distributor = $this->resolveDistributor($ctx, $order);
            $commission = $this->commissionOf($distributor, $netValue)
                + $rewards['commission'];
            if ($commission > 0 && $distributor !== null) {
                AccProfitLedger::create([
                    'network_owner_id' => $ctx->ownerId,
                    'party_type' => 'distributor',
                    'party_id' => $distributor->id,
                    'reason' => 'sale_commission',
                    'delta' => $commission,
                    'ref_type' => 'acc_pos_orders',
                    'ref_id' => $order->id,
                    'agent_id' => $ctx->agentId(),
                    'note' => 'عمولة طلب ' . $order->order_no,
                    'created_at' => now(),
                ]);
                if (Schema::hasTable('acc_commissions')) {
                    AccCommission::accrue(
                        $ctx->ownerId,
                        $distributor->id,
                        Carbon::today()->format('Y-m'),
                        $netValue,
                        $commission
                    );
                }
            }

            // 4) Balanced pos_sale journal entry (idempotent key).
            $this->postEntry(
                $ctx, $order, $pos, $items, $distributor,
                $commission, $netValue, $pointsTotal
            );

            // 5) Status flip + tier snapshot: points_total freezes to
            //    what was actually spent, discount_amount records the
            //    granted tier discount (forward-compatible column).
            $order->status = AccPosOrder::STATUS_APPROVED;
            $order->approved_by = $ctx->user->id;
            $order->approved_at = now();
            $order->points_total = $pointsTotal;
            if ($rewards['discount'] > 0
                && Schema::hasColumn('acc_pos_orders', 'discount_amount')) {
                $order->discount_amount = $rewards['discount'];
            }
            if ($distributor !== null && $order->distributor_id === null) {
                $order->distributor_id = $distributor->id;
            }
            $order->save();

            $this->audit($ctx, 'pos_order.approve', $order->id, [
                'order_no' => $order->order_no,
                'total' => $netValue,
                'discount' => $rewards['discount'],
                'points' => $pointsTotal,
                'commission' => $commission,
                'tiers' => array_map(fn ($t) => $t->id, $rewards['tiers']),
            ]);

            return $order->load('items');
        });
    }

    // ── Reject ───────────────────────────────────────────────────

    public function reject(AccContext $ctx, int $orderId, ?string $reason = null): AccPosOrder
    {
        return DB::transaction(function () use ($ctx, $orderId, $reason) {
            $order = AccPosOrder::where('network_owner_id', $ctx->ownerId)
                ->lockForUpdate()
                ->find($orderId);

            if ($order === null) {
                throw new AccOrderException('الطلب غير موجود', 404);
            }
            if ($order->status === AccPosOrder::STATUS_REJECTED) {
                return $order->load('items');
            }
            if ($order->status === AccPosOrder::STATUS_APPROVED) {
                throw new AccOrderException('لا يمكن رفض طلب معتمد', 409);
            }

            $order->status = AccPosOrder::STATUS_REJECTED;
            $order->reject_reason = $reason;
            $order->save();

            $this->audit($ctx, 'pos_order.reject', $order->id, [
                'order_no' => $order->order_no,
                'reason' => $reason,
            ]);

            return $order->load('items');
        });
    }

    // ── Internals ────────────────────────────────────────────────

    private function resolvePos(AccContext $ctx, int $posId): AccPosPoint
    {
        $pos = AccPosPoint::where('network_owner_id', $ctx->ownerId)->find($posId);
        if ($pos === null) {
            throw new AccOrderException('نقطة البيع غير موجودة');
        }
        if ($pos->status !== AccPosPoint::STATUS_ACTIVE) {
            throw new AccOrderException('نقطة البيع موقوفة');
        }
        // A pos-role account may only order for its own bound point.
        if ($ctx->role === 'pos') {
            $agentId = $ctx->agentId();
            if ($agentId === null || (int) $pos->agent_id !== $agentId) {
                throw new AccOrderException('هذه النقطة غير مرتبطة بحسابك', 403);
            }
        }

        return $pos;
    }

    /**
     * Item prices are authoritative from the ACC-02 catalog when it
     * exists (acc_card_categories); before it lands, submitted
     * prices are snapshotted — an approver always sees server
     * numbers, never trusts the client.
     */
    private function resolveItems(int $ownerId, mixed $raw): array
    {
        if (! is_array($raw) || $raw === []) {
            throw new AccOrderException('الطلب يتطلب صنفاً واحداً على الأقل');
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
                throw new AccOrderException("السطر {$i}: صيغة صنف غير صحيحة");
            }
            $qty = (int) ($row['qty'] ?? 0);
            if ($qty < 1) {
                throw new AccOrderException("السطر {$i}: الكمية يجب أن تكون 1 فأكثر");
            }

            $categoryId = isset($row['category_id']) && $row['category_id'] !== ''
                ? (int) $row['category_id'] : null;
            $cat = $categoryId !== null ? $catalog->get($categoryId) : null;
            if ($categoryId !== null && $catalog->isNotEmpty() && $cat === null) {
                throw new AccOrderException("السطر {$i}: فئة غير موجودة");
            }

            $name = $cat->name ?? ($row['name'] ?? null);
            $unitPrice = isset($cat->sell_price)
                ? (float) $cat->sell_price
                : (float) ($row['unit_price'] ?? 0);
            $unitCost = isset($cat->cost_price)
                ? (float) $cat->cost_price
                : (float) ($row['unit_cost'] ?? 0);

            if ($name === null || $name === '') {
                throw new AccOrderException("السطر {$i}: اسم الصنف مطلوب");
            }
            if ($unitPrice < 0 || $unitCost < 0) {
                throw new AccOrderException("السطر {$i}: مبالغ سالبة مرفوضة");
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

    /**
     * Stock-out per item, only when ACC-02's tables exist — the same
     * forward-compatible pattern AccPostingService uses for
     * acc_sync_queue. Insufficient stock aborts the approval and
     * rolls back the entire transaction.
     */
    private function applyStockOut(AccContext $ctx, AccPosOrder $order, $items): void
    {
        if (! Schema::hasTable('acc_stock') || ! Schema::hasTable('acc_stock_movements')) {
            return;
        }

        foreach ($items as $item) {
            if ($item->category_id === null) {
                continue;
            }

            $stock = DB::table('acc_stock')
                ->where('network_owner_id', $ctx->ownerId)
                ->where('category_id', $item->category_id)
                ->lockForUpdate()
                ->first();
            $available = (float) ($stock->qty ?? 0);
            if ($available < $item->qty) {
                throw new AccOrderException(
                    "مخزون غير كافٍ لـ «{$item->category_name}» — المتاح {$available} والمطلوب {$item->qty}"
                );
            }

            DB::table('acc_stock')
                ->where('id', $stock->id)
                ->update(['qty' => $available - $item->qty, 'updated_at' => now()]);

            DB::table('acc_stock_movements')->insert([
                'network_owner_id' => $ctx->ownerId,
                'category_id' => $item->category_id,
                'type' => 'order_fill',
                'qty' => -$item->qty, // signed: negative = out
                'unit_cost' => (float) $item->unit_cost,
                'ref_type' => 'acc_pos_orders',
                'ref_id' => $order->id,
                'agent_id' => $ctx->agentId(),
                'note' => 'تعبئة طلب ' . $order->order_no,
                'created_at' => now(),
            ]);
        }
    }

    /** The deciding/serving distributor agent, if any. */
    private function resolveDistributor(AccContext $ctx, AccPosOrder $order): ?AccAgent
    {
        if ($order->distributor_id !== null) {
            return AccAgent::where('network_owner_id', $ctx->ownerId)
                ->where('role', 'distributor')
                ->find($order->distributor_id);
        }
        $actor = $ctx->agent;
        if ($actor !== null && $actor->role === 'distributor') {
            return $actor;
        }

        return null;
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

    /**
     * pos_sale entry: prepaid-points part debits the POS's customer
     * balance (points are prepaid value), any remainder goes to AR,
     * revenue is credited once, and COGS moves inventory to expense.
     * The distributor commission accrues as a liability to the
     * agent — one entry, one transaction. ACC-10: $netValue carries
     * the tier-discounted document value and $pointsSpent what the
     * POS actually prepaid (capped at the discounted value).
     */
    private function postEntry(
        AccContext $ctx,
        AccPosOrder $order,
        AccPosPoint $pos,
        $items,
        ?AccAgent $distributor,
        float $commission,
        float $netValue,
        float $pointsSpent
    ): void {
        $value = $netValue;
        $covered = min($pointsSpent, $value);
        $remainder = round($value - $covered, 2);
        $cost = round((float) $items->sum(fn ($i) => $i->qty * (float) $i->unit_cost), 2);

        $lines = [];
        if ($covered > 0) {
            $lines[] = [
                'account_code' => AccAccount::CUSTOMER_BALANCES,
                'party_type' => 'pos', 'party_id' => $pos->id,
                'debit' => $covered, 'credit' => 0,
            ];
        }
        if ($remainder > 0) {
            $lines[] = [
                'account_code' => AccAccount::AR_POS,
                'party_type' => 'pos', 'party_id' => $pos->id,
                'debit' => $remainder, 'credit' => 0,
            ];
        }
        if ($value > 0) {
            $lines[] = [
                'account_code' => AccAccount::REVENUE_SALES,
                'debit' => 0, 'credit' => $value,
            ];
        }
        if ($cost > 0) {
            $lines[] = [
                'account_code' => AccAccount::EXPENSES,
                'debit' => $cost, 'credit' => 0,
            ];
            $lines[] = [
                'account_code' => AccAccount::INVENTORY_CARDS,
                'debit' => 0, 'credit' => $cost,
            ];
        }
        if ($commission > 0 && $distributor !== null) {
            $lines[] = [
                'account_code' => AccAccount::EXPENSES,
                'debit' => $commission, 'credit' => 0,
            ];
            $lines[] = [
                'account_code' => AccAccount::POS_PROFITS,
                'party_type' => 'distributor', 'party_id' => $distributor->id,
                'debit' => 0, 'credit' => $commission,
            ];
        }

        if (count($lines) < 2) {
            // A zero-value order carries no financial effect.
            return;
        }

        $this->posting->post('pos_sale', [
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'doc_ref_id' => $order->id,
            'memo' => 'اعتماد طلب نقطة بيع ' . $order->order_no,
            'idempotency_key' => 'pos-order-' . $order->id . '-approve',
            'lines' => $lines,
        ]);
    }

    private function nextOrderNo(int $ownerId): string
    {
        $prefix = 'PO-' . Carbon::today()->format('Ymd') . '-';
        $last = AccPosOrder::where('network_owner_id', $ownerId)
            ->where('order_no', 'like', $prefix . '%')
            ->lockForUpdate()
            ->max('order_no');

        $seq = $last === null ? 1 : ((int) substr($last, -6)) + 1;

        return $prefix . str_pad((string) $seq, 6, '0', STR_PAD_LEFT);
    }

    private function audit(AccContext $ctx, string $action, int $orderId, array $meta = []): void
    {
        AccAuditLog::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'action' => $action,
            'entity' => 'acc_pos_orders',
            'entity_id' => $orderId,
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }

    private function isUniqueViolation(QueryException $e): bool
    {
        $msg = $e->getMessage();

        return str_contains($msg, 'UNIQUE constraint failed')
            || str_contains($msg, 'Duplicate entry')
            || $e->getCode() === '23000';
    }
}
