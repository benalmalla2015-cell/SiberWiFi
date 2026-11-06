<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccSyncQueue;
use App\Services\AccContext;
use App\Services\AccSyncService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Sync center endpoints (ACC-12, PLAN §4).
 *
 * - GET  /sync/pending — counters + the attention list
 *   (pending + needs_review) for the sync-center header.
 * - GET  /sync/queue   — paginated op log, filterable by status.
 * - POST /sync/push    — the app pushes its offline ops here; each
 *   op replays through its domain service (AccSyncService).
 * - POST /sync/{op}/retry|discard — needs_review handling
 *   (owner/admin through the sync.manage grant).
 */
class AccSyncController extends Controller
{
    public function __construct(private AccSyncService $sync) {}

    public function pending(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $ops = AccSyncQueue::where('network_owner_id', $ctx->ownerId)
            ->whereIn('status', ['pending', 'needs_review'])
            ->latest('id')
            ->limit(50)
            ->get()
            ->map(fn (AccSyncQueue $q) => $this->serialize($q));

        return response()->json([
            'success' => true,
            'counts' => $this->sync->pendingSummary($ctx),
            'data' => $ops,
        ]);
    }

    public function queue(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccSyncQueue::where('network_owner_id', $ctx->ownerId)
            ->latest('id');
        if ($status = $request->query('status')) {
            $query->where('status', $status);
        }

        return response()->json([
            'success' => true,
            'counts' => $this->sync->pendingSummary($ctx),
            'data' => $query->paginate(25)->through(
                fn (AccSyncQueue $q) => $this->serialize($q)
            ),
        ]);
    }

    /**
     * The offline → online handoff. `ops` arrives either as a real
     * array (JSON clients) or a JSON string field (the app's
     * multipart bodies); each item is {client_op_id, op_type,
     * payload, queued_at?}.
     */
    public function push(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $ops = $request->input('ops');
        if (is_string($ops)) {
            $ops = json_decode($ops, true);
        }
        if (! is_array($ops)) {
            return response()->json([
                'success' => false,
                'message' => 'صيغة الطابور غير صالحة',
            ], 422);
        }

        $results = $this->sync->push($ctx, array_values($ops));

        return response()->json([
            'success' => true,
            'message' => 'اكتملت المزامنة',
            'counts' => $this->sync->pendingSummary($ctx),
            'results' => $results,
        ]);
    }

    public function retry(Request $request, int $op): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $result = $this->sync->retry($ctx, $op);

        return response()->json([
            'success' => $result['status'] === 'sent',
            'message' => $result['message'],
            'counts' => $this->sync->pendingSummary($ctx),
            'result' => $result,
        ], $result['status'] === 'sent' ? 200 : 422);
    }

    public function discard(Request $request, int $op): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $this->sync->discard($ctx, $op);

        return response()->json([
            'success' => true,
            'message' => 'تم حذف العملية من الطابور',
            'counts' => $this->sync->pendingSummary($ctx),
        ]);
    }

    private function serialize(AccSyncQueue $q): array
    {
        $envelope = is_array($q->payload) ? $q->payload : [];
        $data = is_array($envelope['data'] ?? null) ? $envelope['data'] : $envelope;

        return [
            'id' => $q->id,
            'client_op_id' => $q->client_op_id,
            'op_type' => $q->op_type,
            'label' => $envelope['label'] ?? $data['label'] ?? $this->opLabel($q->op_type),
            'status' => $q->status,
            'attempts' => (int) $q->attempts,
            'last_error' => $q->last_error,
            'ref_id' => (int) ($q->result['ref_id'] ?? 0) ?: null,
            'queued_at' => $envelope['queued_at'] ?? null,
            'sent_at' => $q->sent_at?->toISOString(),
            'created_at' => $q->created_at?->toISOString(),
        ];
    }

    /** Fallback Arabic label when the app didn't send one. */
    private function opLabel(string $opType): string
    {
        if (str_starts_with($opType, 'post:')) {
            return 'قيد ترحيل — ' . substr($opType, 5);
        }

        return self::OP_LABELS[$opType] ?? $opType;
    }

    private const OP_LABELS = [
        'collection.create' => 'تحصيل نقدي',
        'debt.create' => 'تسجيل دين',
        'debt.pay' => 'سداد دين',
        'expense.create' => 'مصروف',
        'transfer.create' => 'تحويل بين الصناديق',
        'dist.sale' => 'بيع موزع',
        'pos.order' => 'طلب نقطة بيع',
        'pos.withdrawal' => 'طلب سحب ربح',
        'pos.exchange' => 'استبدال كروت بالنقاط',
        'stock.adjust' => 'تسوية مخزون',
        'purchase.create' => 'مشتريات',
        'return.create' => 'مرتجع',
        'damaged.create' => 'تالف',
    ];
}
