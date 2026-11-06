<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccCashBox;
use App\Models\AccCashTransfer;
use App\Services\AccContext;
use App\Services\AccMoneyException;
use App\Services\AccMoneyService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Cash boxes + inter-box transfers (ACC-05, PLAN §2.3 + §4).
 * Boxes are plain CRUD for owner/admin; transfers run through
 * AccMoneyService so both drawer balances and the journal entry
 * commit in one transaction.
 */
class AccCashBoxesController extends Controller
{
    public function __construct(private AccMoneyService $money) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        AccCashBox::ensureDefaultFor($ctx->ownerId);

        $boxes = AccCashBox::where('network_owner_id', $ctx->ownerId)
            ->orderByDesc('is_default')
            ->orderBy('name')
            ->get()
            ->map(fn (AccCashBox $b) => $this->serialize($b));

        return response()->json(['success' => true, 'data' => $boxes]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'name' => 'required|string|max:190',
            'currency' => 'nullable|string|in:north,south',
            'opening_balance' => 'nullable|numeric|min:0',
        ]);

        try {
            $box = $this->money->createBox($ctx, $data);
        } catch (AccMoneyException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء الصندوق',
            'data' => $this->serialize($box),
        ], 201);
    }

    public function update(Request $request, int $box): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccCashBox::where('network_owner_id', $ctx->ownerId)->find($box);
        if ($model === null) {
            return response()->json(['success' => false, 'message' => 'الصندوق غير موجود'], 404);
        }

        $data = $request->validate([
            'name' => 'sometimes|string|max:190',
            'is_active' => 'sometimes|boolean',
        ]);

        // The default box must always stay usable — deactivating it
        // would strand every money movement without a target.
        if (array_key_exists('is_active', $data) && ! $data['is_active'] && $model->is_default) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن إيقاف الصندوق الرئيسي',
            ], 422);
        }

        $model->update($data);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الصندوق',
            'data' => $this->serialize($model),
        ]);
    }

    public function transfers(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $transfers = AccCashTransfer::with(['fromBox:id,name', 'toBox:id,name'])
            ->where('network_owner_id', $ctx->ownerId)
            ->latest()
            ->paginate(25)
            ->through(fn (AccCashTransfer $t) => [
                'id' => $t->id,
                'from_box_id' => $t->from_box_id,
                'from_box_name' => $t->fromBox?->name,
                'to_box_id' => $t->to_box_id,
                'to_box_name' => $t->toBox?->name,
                'amount' => (float) $t->amount,
                'to_amount' => (float) $t->to_amount,
                'currency' => $t->currency,
                'journal_entry_id' => $t->journal_entry_id,
                'note' => $t->note,
                'created_at' => $t->created_at?->toISOString(),
            ]);

        return response()->json(['success' => true, 'data' => $transfers]);
    }

    public function transfer(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'from_box_id' => 'required|integer',
            'to_box_id' => 'required|integer|different:from_box_id',
            'amount' => 'required|numeric|min:0.01',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ]);

        try {
            $transfer = $this->money->transfer($ctx, $data);
        } catch (AccMoneyException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم التحويل وترحيله',
            'data' => [
                'id' => $transfer->id,
                'from_box_id' => $transfer->from_box_id,
                'to_box_id' => $transfer->to_box_id,
                'amount' => (float) $transfer->amount,
                'to_amount' => (float) $transfer->to_amount,
                'journal_entry_id' => $transfer->journal_entry_id,
            ],
        ], 201);
    }

    private function serialize(AccCashBox $b): array
    {
        return [
            'id' => $b->id,
            'name' => $b->name,
            'currency' => $b->currency,
            'balance' => (float) $b->balance,
            'is_default' => $b->is_default,
            'is_active' => $b->is_active,
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
