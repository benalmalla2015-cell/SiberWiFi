<?php

namespace App\Services;

use App\Models\AccPosPoint;
use App\Models\AccSyncQueue;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * ACC-12 — offline sync engine (PLAN §2.5 + §3).
 *
 * The app captures write-ops while offline and pushes them through
 * POST /sync/push once connectivity returns. Each op carries a
 * device-generated client_op_id → pushing the same batch twice is a
 * free replay, never a duplicate post (same guarantee as
 * idempotency_key on journal entries).
 *
 * Dispatch is a whitelist: every op_type maps to the same domain
 * service the online endpoint uses, with the same validation rules
 * as its controller — so a queued collection posts the identical
 * balanced entry it would have posted online.
 *
 * A second producer exists: AccPostingService::queueFailedOp parks
 * `post:{doc_type}` rows here as needs_review; retry re-runs the
 * post, discard drops the row.
 */
class AccSyncService
{
    /**
     * Validation rules per op_type — mirrored from the owning
     * controller so an op rejected online is rejected the same way
     * when replayed from the queue. Returned from a method (not a
     * const) because some rules use Rule::in() objects.
     */
    private function opRules(string $opType): ?array
    {
        $rules = [
        'collection.create' => [
            'party_type' => 'required|string|in:pos,distributor,customer,person',
            'party_id' => 'nullable|integer',
            'party_name' => 'nullable|string|max:190',
            'phone' => 'nullable|string|max:30',
            'amount' => 'required|numeric|min:0.01',
            'currency' => 'nullable|string|in:north,south',
            'cash_box_id' => 'nullable|integer',
            'collected_at' => 'nullable|date',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ],
        'debt.create' => [
            'party_type' => 'required|string|in:pos,distributor,customer,person,supplier',
            'party_id' => 'nullable|integer',
            'party_name' => 'nullable|string|max:190',
            'phone' => 'nullable|string|max:30',
            'amount_due' => 'required|numeric|min:0.01',
            'currency' => 'nullable|string|in:north,south',
            'due_date' => 'nullable|date',
            'post_entry' => 'nullable|boolean',
            'note' => 'nullable|string|max:190',
        ],
        'debt.pay' => [
            'debt_id' => 'required|integer',
            'amount' => 'required|numeric|min:0.01',
            'cash_box_id' => 'nullable|integer',
            'paid_at' => 'nullable|date',
            'note' => 'nullable|string|max:190',
        ],
        'expense.create' => [
            'category_id' => 'nullable|integer',
            'category_name' => 'nullable|string|max:190',
            'amount' => 'required|numeric|min:0.01',
            'currency' => 'nullable|string|in:north,south',
            'cash_box_id' => 'nullable|integer',
            'incurred_at' => 'nullable|date',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ],
        'transfer.create' => [
            'from_box_id' => 'required|integer',
            'to_box_id' => 'required|integer|different:from_box_id',
            'amount' => 'required|numeric|min:0.01',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ],
        'dist.sale' => [
            'pos_id' => 'required|integer',
            'items' => 'required|array|min:1',
            'items.*.category_id' => 'nullable|integer',
            'items.*.name' => 'nullable|string|max:190',
            'items.*.qty' => 'required|integer|min:1',
            'items.*.unit_price' => 'nullable|numeric|min:0',
            'items.*.unit_cost' => 'nullable|numeric|min:0',
            'payment_kind' => 'required|string|in:cash,credit,partial',
            'paid_amount' => 'nullable|numeric|min:0',
            'currency' => 'nullable|string|in:north,south',
            'cash_box_id' => 'nullable|integer',
            'due_date' => 'nullable|date',
            'distributor_id' => 'nullable|integer',
            'sold_at' => 'nullable|date',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ],
        'pos.order' => [
            'pos_id' => 'nullable|integer',
            'items' => 'required|array|min:1',
            'items.*.category_id' => 'nullable|integer',
            'items.*.name' => 'nullable|string|max:190',
            'items.*.qty' => 'required|integer|min:1',
            'items.*.unit_price' => 'nullable|numeric|min:0',
            'items.*.unit_cost' => 'nullable|numeric|min:0',
            'points_total' => 'nullable|numeric|min:0',
            'distributor_id' => 'nullable|integer',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ],
        'pos.withdrawal' => [
            'amount' => 'required|numeric|min:0.01',
            'receiver_name' => 'nullable|string|max:190',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ],
        'pos.exchange' => [
            'category_id' => 'required|integer',
            'qty' => 'required|integer|min:1',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ],
        'stock.adjust' => [
            'category_id' => 'required|integer',
            'qty' => 'required|numeric|min:0',
            'note' => 'nullable|string|max:190',
        ],
        'purchase.create' => [
            'supplier_id' => 'nullable|integer',
            'category_id' => 'required|integer',
            'invoice_no' => 'nullable|string|max:64',
            'qty' => 'required|numeric|min:0.01',
            'unit_price' => 'required|numeric|min:0',
            'currency' => 'nullable|string|max:8',
            'exchange_rate' => 'nullable|numeric|min:0.000001',
            'payment' => ['nullable', Rule::in(['cash', 'credit'])],
            'date' => 'nullable|date',
            'note' => 'nullable|string|max:190',
        ],
        'return.create' => [
            'kind' => ['required', Rule::in(['purchase_return', 'sale_return', 'card_return'])],
            'ref_type' => 'nullable|string|max:32',
            'ref_id' => 'nullable|integer',
            'category_id' => 'required|integer',
            'qty' => 'required|numeric|min:0.01',
            'amount' => 'nullable|numeric|min:0',
            'reason' => 'nullable|string|max:190',
            'date' => 'nullable|date',
        ],
        'damaged.create' => [
            'category_id' => 'required|integer',
            'qty' => 'required|numeric|min:0.01',
            'unit_cost' => 'nullable|numeric|min:0',
            'reason' => 'nullable|string|max:190',
            'evidence_note' => 'nullable|string|max:190',
            'date' => 'nullable|date',
        ],
        ];

        return $rules[$opType] ?? null;
    }

    /**
     * The date/datetime field each op type stamps with the original
     * queue time when the payload didn't carry one — an offline
     * collection keeps its real collection moment, not sync time.
     */
    private const DATE_FIELD = [
        'collection.create' => 'collected_at',
        'debt.pay' => 'paid_at',
        'expense.create' => 'incurred_at',
        'dist.sale' => 'sold_at',
        'purchase.create' => 'date',
        'return.create' => 'date',
        'damaged.create' => 'date',
    ];

    public function __construct(
        private AccMoneyService $money,
        private AccDistService $dist,
        private AccPosOrderService $orders,
        private AccPosAppService $posApp,
        private AccStockService $stock,
        private AccPostingService $posting,
    ) {}

    /**
     * Push a batch of offline ops. Every op is processed inside its
     * own transaction — one bad op never blocks the rest of the batch.
     *
     * @param  list<array{client_op_id?:string,op_type?:string,payload?:array,queued_at?:string}>  $ops
     * @return list<array{client_op_id:?string,status:string,message:string,ref_id:?int}>
     */
    public function push(AccContext $ctx, array $ops): array
    {
        $results = [];
        foreach ($ops as $op) {
            $results[] = $this->pushOne($ctx, is_array($op) ? $op : []);
        }

        return $results;
    }

    private function pushOne(AccContext $ctx, array $op): array
    {
        $clientOpId = substr(trim((string) ($op['client_op_id'] ?? '')), 0, 64);
        $opType = trim((string) ($op['op_type'] ?? ''));
        $payload = is_array($op['payload'] ?? null) ? $op['payload'] : [];

        if ($clientOpId === '') {
            return ['client_op_id' => null, 'status' => 'rejected',
                'message' => 'client_op_id مفقود', 'ref_id' => null];
        }

        // Replayable: the same client_op_id can never post twice.
        $row = AccSyncQueue::where('network_owner_id', $ctx->ownerId)
            ->where('client_op_id', $clientOpId)
            ->first();

        if ($row !== null && $row->status === AccSyncQueue::STATUS_SENT) {
            return ['client_op_id' => $clientOpId, 'status' => 'replayed',
                'message' => 'مُزامَنة سابقاً', 'ref_id' => (int) ($row->result['ref_id'] ?? 0) ?: null];
        }

        if ($row === null) {
            $row = AccSyncQueue::create([
                'network_owner_id' => $ctx->ownerId,
                'client_op_id' => $clientOpId,
                'op_type' => $opType,
                'payload' => [
                    'data' => $payload,
                    'queued_at' => $op['queued_at'] ?? null,
                    'label' => $op['label'] ?? null,
                ],
                'status' => AccSyncQueue::STATUS_PENDING,
            ]);
        } else {
            // A returning push may carry a corrected payload — adopt it.
            $row->payload = [
                'data' => $payload,
                'queued_at' => $op['queued_at'] ?? null,
                'label' => $op['label'] ?? null,
            ];
        }

        return $this->runOp($ctx, $row, $clientOpId);
    }

    /**
     * Re-dispatch a queued row (needs_review or stranded pending) —
     * used by POST /sync/{op}/retry from the sync center.
     */
    public function retry(AccContext $ctx, int $opId): array
    {
        $row = $this->ownedOp($ctx, $opId);

        return $this->runOp($ctx, $row, $row->client_op_id);
    }

    /** Drop a stuck op — queue rows are an ops log, never a ledger. */
    public function discard(AccContext $ctx, int $opId): void
    {
        $this->ownedOp($ctx, $opId)->delete();
    }

    public function ownedOp(AccContext $ctx, int $opId): AccSyncQueue
    {
        $row = AccSyncQueue::where('network_owner_id', $ctx->ownerId)->find($opId);
        abort_if($row === null, 404, 'العملية غير موجودة');

        return $row;
    }

    /** Counters + attention list for GET /sync/pending. */
    public function pendingSummary(AccContext $ctx): array
    {
        $base = AccSyncQueue::where('network_owner_id', $ctx->ownerId);

        return [
            'pending' => (clone $base)->where('status', 'pending')->count(),
            'sent' => (clone $base)->where('status', 'sent')->count(),
            'needs_review' => (clone $base)->where('status', 'needs_review')->count(),
        ];
    }

    // ── Dispatch ─────────────────────────────────────────────────

    private function runOp(AccContext $ctx, AccSyncQueue $row, ?string $clientOpId): array
    {
        $row->attempts = (int) $row->attempts + 1;

        try {
            $refId = DB::transaction(fn () => $this->dispatch($ctx, $row));
            $row->status = AccSyncQueue::STATUS_SENT;
            $row->last_error = null;
            $row->result = ['ref_id' => $refId];
            $row->sent_at = now();
            $row->save();

            return ['client_op_id' => $clientOpId, 'status' => 'sent',
                'message' => 'تمت المزامنة وترحيلها', 'ref_id' => $refId];
        } catch (\Throwable $e) {
            $row->status = AccSyncQueue::STATUS_NEEDS_REVIEW;
            $row->last_error = mb_substr($this->errorMessage($e), 0, 1900);
            $row->save();

            return ['client_op_id' => $clientOpId, 'status' => 'needs_review',
                'message' => $row->last_error, 'ref_id' => null];
        }
    }

    /**
     * Route one queued row to its domain service and return the
     * created entity id. Throws on validation/business failure —
     * the caller parks the row as needs_review.
     */
    private function dispatch(AccContext $ctx, AccSyncQueue $row): ?int
    {
        $opType = (string) $row->op_type;
        $envelope = is_array($row->payload) ? $row->payload : [];
        // Posting-hook rows store {doc, error}; app ops store {data, queued_at}.
        $data = is_array($envelope['data'] ?? null) ? $envelope['data'] : $envelope;

        if (str_starts_with($opType, 'post:')) {
            $doc = is_array($envelope['doc'] ?? null) ? $envelope['doc'] : $data;
            $doc['network_owner_id'] = $ctx->ownerId;

            return $this->posting->post(substr($opType, 5), $doc)->id;
        }

        $rules = $this->opRules($opType);
        if ($rules === null) {
            throw new AccOrderException("نوع عملية غير مدعوم: {$opType}");
        }

        $data = Validator::make($data, $rules)->validate();
        if (($dateField = self::DATE_FIELD[$opType] ?? null) !== null
            && empty($data[$dateField]) && ! empty($envelope['queued_at'])) {
            $data[$dateField] = (string) $envelope['queued_at'];
        }

        return match ($opType) {
            'collection.create' => $this->money->collect($ctx, $data)->id,
            'debt.create' => $this->money->createDebt($ctx, $data)->id,
            'debt.pay' => $this->money->payDebt($ctx, (int) $data['debt_id'], $data)->id,
            'expense.create' => $this->money->expense($ctx, $data)->id,
            'transfer.create' => $this->money->transfer($ctx, $data)->id,
            'dist.sale' => $this->dist->sale($ctx, $data)->id,
            'pos.order' => $this->orders->create($ctx, $this->withPosId($ctx, $data))->id,
            'pos.withdrawal' => $this->posApp->requestWithdrawal($ctx, $data)->id,
            'pos.exchange' => $this->posApp->exchange($ctx, $data)->id,
            'stock.adjust' => $this->stock->adjust(
                $ctx, (int) $data['category_id'], (float) $data['qty'], $data['note'] ?? null
            )->id,
            'purchase.create' => $this->stock->recordPurchase($ctx, $data)->id,
            'return.create' => $this->stock->recordReturn($ctx, $data)->id,
            'damaged.create' => $this->stock->recordDamaged($ctx, $data)->id,
            default => throw new AccOrderException("نوع عملية غير مدعوم: {$opType}"),
        };
    }

    /**
     * A pos agent can only order for its own bound point — mirrors
     * AccPosOrdersController::storeMyOrder. Managers pass pos_id
     * explicitly, same as POST /pos-orders.
     */
    private function withPosId(AccContext $ctx, array $data): array
    {
        if ($ctx->role === 'pos') {
            $agentId = $ctx->agentId();
            $pos = $agentId === null ? null : AccPosPoint::where('network_owner_id', $ctx->ownerId)
                ->where('agent_id', $agentId)
                ->where('status', AccPosPoint::STATUS_ACTIVE)
                ->first();
            if ($pos === null) {
                throw new AccOrderException('لا توجد نقطة بيع نشطة مرتبطة بحسابك', 403);
            }
            $data['pos_id'] = $pos->id;
        }

        return $data;
    }

    private function errorMessage(\Throwable $e): string
    {
        if ($e instanceof ValidationException) {
            $first = collect($e->errors())->flatten()->first();

            return is_string($first) && $first !== '' ? $first : 'بيانات العملية غير مكتملة';
        }

        return $e->getMessage() !== '' ? $e->getMessage() : 'تعذر تنفيذ العملية';
    }
}
