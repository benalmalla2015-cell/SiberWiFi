<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccExpense;
use App\Models\AccExpenseCategory;
use App\Services\AccContext;
use App\Services\AccMoneyException;
use App\Services\AccMoneyService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Daily expenses + their categories (ACC-05, PLAN §2.3 + §4).
 * POST posts `Dr expenses / Cr cash box` atomically; DELETE voids
 * the document through a reversal entry — rows are never removed.
 */
class AccExpensesController extends Controller
{
    public function __construct(private AccMoneyService $money) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccExpense::with('box:id,name')
            ->where('network_owner_id', $ctx->ownerId)
            ->latest('incurred_at');

        if ($categoryId = $request->query('category_id')) {
            $query->where('category_id', (int) $categoryId);
        }
        if ($from = $request->query('from')) {
            $query->whereDate('incurred_at', '>=', $from);
        }
        if ($to = $request->query('to')) {
            $query->whereDate('incurred_at', '<=', $to);
        }
        if ($request->boolean('with_void') !== true) {
            $query->where('status', AccExpense::STATUS_POSTED);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccExpense $e) => $this->serialize($e)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'category_id' => 'nullable|integer',
            'category_name' => 'nullable|string|max:190',
            'amount' => 'required|numeric|min:0.01',
            'currency' => 'nullable|string|in:north,south',
            'cash_box_id' => 'nullable|integer',
            'incurred_at' => 'nullable|date',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ]);

        try {
            $expense = $this->money->expense($ctx, $data);
        } catch (AccMoneyException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل المصروف وترحيله',
            'data' => $this->serialize($expense),
        ], 201);
    }

    /** Void the expense — posts a reversal entry, keeps the row. */
    public function destroy(Request $request, int $expense): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        try {
            $model = $this->money->voidExpense($ctx, $expense);
        } catch (AccMoneyException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إلغاء المصروف بقيد عكسي',
            'data' => $this->serialize($model),
        ]);
    }

    // ── Categories ───────────────────────────────────────────────

    public function categories(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        AccExpenseCategory::ensureDefaultsFor($ctx->ownerId);

        $categories = AccExpenseCategory::where('network_owner_id', $ctx->ownerId)
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get()
            ->map(fn (AccExpenseCategory $c) => [
                'id' => $c->id,
                'name' => $c->name,
                'sort_order' => $c->sort_order,
                'is_active' => $c->is_active,
            ]);

        return response()->json(['success' => true, 'data' => $categories]);
    }

    public function storeCategory(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'name' => 'required|string|max:190',
            'sort_order' => 'nullable|integer|min:0',
        ]);

        AccExpenseCategory::ensureDefaultsFor($ctx->ownerId);
        $exists = AccExpenseCategory::where('network_owner_id', $ctx->ownerId)
            ->where('name', $data['name'])
            ->exists();
        if ($exists) {
            return response()->json([
                'success' => false,
                'message' => 'الفئة موجودة مسبقاً',
            ], 422);
        }

        $category = AccExpenseCategory::create([
            'network_owner_id' => $ctx->ownerId,
            'name' => $data['name'],
            'sort_order' => (int) ($data['sort_order'] ?? 99),
            'is_active' => true,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'تمت إضافة الفئة',
            'data' => [
                'id' => $category->id,
                'name' => $category->name,
                'sort_order' => $category->sort_order,
                'is_active' => $category->is_active,
            ],
        ], 201);
    }

    public function updateCategory(Request $request, int $category): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccExpenseCategory::where('network_owner_id', $ctx->ownerId)->find($category);
        if ($model === null) {
            return response()->json(['success' => false, 'message' => 'الفئة غير موجودة'], 404);
        }

        $data = $request->validate([
            'name' => 'sometimes|string|max:190',
            'sort_order' => 'sometimes|integer|min:0',
            'is_active' => 'sometimes|boolean',
        ]);
        $model->update($data);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الفئة',
            'data' => [
                'id' => $model->id,
                'name' => $model->name,
                'sort_order' => $model->sort_order,
                'is_active' => $model->is_active,
            ],
        ]);
    }

    /** Categories deactivate — historical expenses keep the name. */
    public function destroyCategory(Request $request, int $category): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccExpenseCategory::where('network_owner_id', $ctx->ownerId)->find($category);
        if ($model === null) {
            return response()->json(['success' => false, 'message' => 'الفئة غير موجودة'], 404);
        }

        $model->update(['is_active' => false]);

        return response()->json([
            'success' => true,
            'message' => 'تم إيقاف الفئة',
        ]);
    }

    private function serialize(AccExpense $e): array
    {
        return [
            'id' => $e->id,
            'category_id' => $e->category_id,
            'category_name' => $e->category_name,
            'amount' => (float) $e->amount,
            'currency' => $e->currency,
            'exchange_rate' => (float) $e->exchange_rate,
            'base_amount' => (float) $e->base_amount,
            'cash_box_id' => $e->cash_box_id,
            'box_name' => $e->box?->name,
            'status' => $e->status,
            'journal_entry_id' => $e->journal_entry_id,
            'incurred_at' => $e->incurred_at?->toISOString(),
            'note' => $e->note,
            'created_at' => $e->created_at?->toISOString(),
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
