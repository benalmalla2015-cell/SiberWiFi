<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccAgent;
use App\Models\AccCollection;
use App\Models\AccPosPoint;
use App\Services\AccContext;
use App\Services\AccMoneyException;
use App\Services\AccMoneyService;
use App\Services\AccWebhookService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Cash collections (ACC-05, PLAN §2.3 + §4). Management list +
 * create on `/collections`; distributors reach the same actions
 * through `/dist/collections` (their collections.* grant); the POS
 * surface `/pos/collections-received` shows a pos agent the
 * collections recorded against its own bound point.
 */
class AccCollectionsController extends Controller
{
    public function __construct(
        private AccMoneyService $money,
        private AccWebhookService $webhooks,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccCollection::with('box:id,name')
            ->where('network_owner_id', $ctx->ownerId)
            ->latest('collected_at');

        if ($type = $request->query('party_type')) {
            $query->where('party_type', $type);
        }
        if ($id = $request->query('party_id')) {
            $query->where('party_id', (int) $id);
        }
        if ($from = $request->query('from')) {
            $query->whereDate('collected_at', '>=', $from);
        }
        if ($to = $request->query('to')) {
            $query->whereDate('collected_at', '<=', $to);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccCollection $c) => $this->serialize($c)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
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
        ]);

        try {
            $collection = $this->money->collect($ctx, $data);
        } catch (AccMoneyException $e) {
            return $this->fail($e);
        }

        // ACC-10 — collection.created templates render after commit.
        $notifications = $this->webhooks->dispatch(
            $ctx->ownerId,
            $ctx->agentId(),
            'collection.created',
            [
                'party_name' => $collection->party_name,
                'amount' => (float) $collection->amount,
                'total' => (float) $collection->amount,
                'currency' => $collection->currency,
                'box' => $collection->box?->name,
                'date' => $collection->collected_at?->toDateString(),
            ],
            [$this->partyRecipient($ctx, $collection)]
        );

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل التحصيل وترحيله',
            'data' => $this->serialize($collection),
            'notifications' => $notifications,
        ], 201);
    }

    /** Collections recorded against the caller's own POS point. */
    public function received(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $agentId = $ctx->agentId();
        $pos = $agentId === null ? null : AccPosPoint::where('network_owner_id', $ctx->ownerId)
            ->where('agent_id', $agentId)
            ->where('status', AccPosPoint::STATUS_ACTIVE)
            ->first();

        if ($pos === null) {
            return response()->json([
                'success' => false,
                'code' => 'no_pos_point',
                'message' => 'لا توجد نقطة بيع نشطة مرتبطة بحسابك',
            ], 403);
        }

        $collections = AccCollection::with('box:id,name')
            ->where('network_owner_id', $ctx->ownerId)
            ->where('party_type', 'pos')
            ->where('party_id', $pos->id)
            ->latest('collected_at')
            ->paginate(25);

        return response()->json([
            'success' => true,
            'data' => $collections->through(fn (AccCollection $c) => $this->serialize($c)),
            'pos' => ['id' => $pos->id, 'name' => $pos->name],
        ]);
    }

    /** ACC-10 — resolve the notification recipient for a collection. */
    private function partyRecipient(AccContext $ctx, AccCollection $c): array
    {
        if ($c->party_type === 'pos' && $c->party_id !== null) {
            $pos = AccPosPoint::where('network_owner_id', $ctx->ownerId)->find($c->party_id);
            if ($pos !== null) {
                return $this->webhooks->posRecipient($pos);
            }
        }
        if ($c->party_type === 'distributor' && $c->party_id !== null) {
            $agent = AccAgent::where('network_owner_id', $ctx->ownerId)->find($c->party_id);
            if ($agent !== null) {
                return $this->webhooks->agentRecipient($agent);
            }
        }

        return $this->webhooks->partyRecipient($c->party_name, $c->phone);
    }

    private function serialize(AccCollection $c): array
    {
        return [
            'id' => $c->id,
            'party_type' => $c->party_type,
            'party_id' => $c->party_id,
            'party_name' => $c->party_name,
            'phone' => $c->phone,
            'amount' => (float) $c->amount,
            'currency' => $c->currency,
            'exchange_rate' => (float) $c->exchange_rate,
            'base_amount' => (float) $c->base_amount,
            'cash_box_id' => $c->cash_box_id,
            'box_name' => $c->box?->name,
            'debt_id' => $c->debt_id,
            'collector_agent_id' => $c->collector_agent_id,
            'journal_entry_id' => $c->journal_entry_id,
            'collected_at' => $c->collected_at?->toISOString(),
            'note' => $c->note,
            'created_at' => $c->created_at?->toISOString(),
        ];
    }

    private function fail(AccMoneyException $e): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => $e->getMessage(),
        ], $e->status);
    }
}
