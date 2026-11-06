<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccPosOrder;
use App\Models\AccPosOrderItem;
use App\Models\AccPosPoint;
use App\Services\AccContext;
use App\Services\AccOrderException;
use App\Services\AccPosOrderService;
use App\Services\AccWebhookService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POS bundle orders — the ACC-04 document cycle (PLAN §2.2, §4).
 *
 * Management surface (/pos-orders): list + create-on-behalf +
 * approve/reject — owner/admin always, distributors via their
 * pos-orders.* grants. POS surface (/pos/orders): a pos agent sees
 * and submits orders for its own bound point only. Every query is
 * tenant-scoped through AccContext.
 */
class AccPosOrdersController extends Controller
{
    public function __construct(
        private AccPosOrderService $orders,
        private AccWebhookService $webhooks,
    ) {}

    // ── Management surface (owner/admin/distributor) ─────────────

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccPosOrder::with([
                'pos:id,name,points_balance',
                'distributor:id,display_name',
                'items',
            ])
            ->where('network_owner_id', $ctx->ownerId)
            ->latest();

        if ($status = $request->query('status')) {
            $query->where('status', $status);
        }
        if ($posId = $request->query('pos_id')) {
            $query->where('pos_id', (int) $posId);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccPosOrder $o) => $this->serialize($o)),
        ]);
    }

    /** Create an order on behalf of a POS point (desk order). */
    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'pos_id' => 'required|integer',
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
        ]);

        try {
            $order = $this->orders->create($ctx, $data);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال الطلب',
            'data' => $this->serialize($order),
        ], 201);
    }

    public function approve(Request $request, int $order): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        try {
            $model = $this->orders->approve($ctx, $order);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        // ACC-10 — approving a POS order is a sale event for the
        // webhook templates; dispatched after commit.
        $pos = $model->pos;
        $notifications = $pos === null ? [] : $this->webhooks->dispatch(
            $ctx->ownerId,
            $ctx->agentId(),
            'sale.created',
            [
                'pos_name' => $pos->name,
                'party_name' => $pos->name,
                'order_no' => $model->order_no,
                'total' => (float) $model->total_amount,
                'paid' => (float) $model->points_total,
                'currency' => 'نقاط',
                'date' => $model->approved_at?->toDateString(),
            ],
            [$this->webhooks->posRecipient($pos)]
        );

        return response()->json([
            'success' => true,
            'message' => 'تم اعتماد الطلب وترحيله',
            'data' => $this->serialize($model),
            'notifications' => $notifications,
        ]);
    }

    public function reject(Request $request, int $order): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate(['reason' => 'nullable|string|max:190']);

        try {
            $model = $this->orders->reject($ctx, $order, $data['reason'] ?? null);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم رفض الطلب',
            'data' => $this->serialize($model),
        ]);
    }

    // ── POS surface (pos agent — own bound point only) ───────────

    public function myOrders(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $pos = $this->ownPoint($ctx);
        if ($pos instanceof JsonResponse) {
            return $pos;
        }

        $query = AccPosOrder::with('items')
            ->where('network_owner_id', $ctx->ownerId)
            ->where('pos_id', $pos->id)
            ->latest();

        if ($status = $request->query('status')) {
            $query->where('status', $status);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccPosOrder $o) => $this->serialize($o)),
            'pos' => [
                'id' => $pos->id,
                'name' => $pos->name,
                'points_balance' => (float) $pos->points_balance,
                'profit_balance' => (float) $pos->profit_balance,
            ],
        ]);
    }

    public function storeMyOrder(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $pos = $this->ownPoint($ctx);
        if ($pos instanceof JsonResponse) {
            return $pos;
        }

        $data = $request->validate([
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
        ]);
        $data['pos_id'] = $pos->id;

        try {
            $order = $this->orders->create($ctx, $data);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال الطلب',
            'data' => $this->serialize($order),
        ], 201);
    }

    // ── Internals ────────────────────────────────────────────────

    /** The POS point bound to this pos agent, or a 403 response. */
    private function ownPoint(AccContext $ctx): AccPosPoint|JsonResponse
    {
        $agentId = $ctx->agentId();
        $pos = $agentId === null ? null : AccPosPoint::where('network_owner_id', $ctx->ownerId)
            ->where('agent_id', $agentId)
            ->where('status', AccPosPoint::STATUS_ACTIVE)
            ->first();

        return $pos ?? response()->json([
            'success' => false,
            'code' => 'no_pos_point',
            'message' => 'لا توجد نقطة بيع نشطة مرتبطة بحسابك',
        ], 403);
    }

    private function serialize(AccPosOrder $o): array
    {
        return [
            'id' => $o->id,
            'order_no' => $o->order_no,
            'pos_id' => $o->pos_id,
            'pos_name' => $o->pos?->name,
            'pos_points_balance' => $o->pos !== null ? (float) $o->pos->points_balance : null,
            'distributor_id' => $o->distributor_id,
            'distributor_name' => $o->distributor?->display_name,
            'requested_by' => $o->requested_by,
            'status' => $o->status,
            'total_amount' => (float) $o->total_amount,
            'discount_amount' => (float) ($o->discount_amount ?? 0),
            'points_total' => (float) $o->points_total,
            'note' => $o->note,
            'reject_reason' => $o->reject_reason,
            'approved_by' => $o->approved_by,
            'approved_at' => $o->approved_at?->toISOString(),
            'items' => $o->items->map(fn (AccPosOrderItem $i) => [
                'id' => $i->id,
                'category_id' => $i->category_id,
                'category_name' => $i->category_name,
                'qty' => $i->qty,
                'unit_price' => (float) $i->unit_price,
                'unit_cost' => (float) $i->unit_cost,
                'line_total' => (float) $i->line_total,
            ])->values(),
            'created_at' => $o->created_at?->toISOString(),
        ];
    }

    private function fail(AccOrderException $e): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => $e->getMessage(),
        ], $e->status);
    }
}
