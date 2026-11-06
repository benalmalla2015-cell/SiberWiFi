<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccCardCategory;
use App\Models\AccAuditLog;
use App\Services\AccContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * CRUD for the accounting card catalog (PLAN §2.1). Each row also
 * carries its live stock balance so the categories screen renders
 * quantities without a second call.
 */
class AccCategoriesController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccCardCategory::with('stock')
            ->where('network_owner_id', $ctx->ownerId)
            ->orderBy('sort_order')
            ->orderBy('id');

        if ($request->has('active')) {
            $query->where('is_active', $request->boolean('active'));
        }

        return response()->json([
            'success' => true,
            'data' => $query->get()->map(fn (AccCardCategory $c) => $this->serialize($c)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $this->validateData($request);

        $category = AccCardCategory::create([
            'network_owner_id' => $ctx->ownerId,
            ...$data,
        ]);

        $this->audit($ctx, 'category.create', $category->id, ['name' => $category->name]);

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء الفئة',
            'data' => $this->serialize($category->load('stock')),
        ], 201);
    }

    public function update(Request $request, int $category): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccCardCategory::where('network_owner_id', $ctx->ownerId)->findOrFail($category);

        $model->update($this->validateData($request, partial: true));
        $this->audit($ctx, 'category.update', $model->id, []);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الفئة',
            'data' => $this->serialize($model->fresh('stock')),
        ]);
    }

    public function destroy(Request $request, int $category): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccCardCategory::where('network_owner_id', $ctx->ownerId)->findOrFail($category);

        // The stock ledger is immutable — a used category is archived
        // (is_active=false) rather than deleted so its history stays.
        $hasMovements = $model->stock()->exists()
            || \App\Models\AccStockMovement::where('category_id', $model->id)->exists();
        if ($hasMovements) {
            return response()->json([
                'success' => false,
                'message' => 'للفئة حركات مخزون — عطّلها بدلاً من حذفها',
            ], 422);
        }

        $model->delete();
        $this->audit($ctx, 'category.delete', $category, ['name' => $model->name]);

        return response()->json(['success' => true, 'message' => 'تم حذف الفئة']);
    }

    private function validateData(Request $request, bool $partial = false): array
    {
        $req = $partial ? 'sometimes' : 'required';

        return $request->validate([
            'name' => "{$req}|string|max:190",
            'sell_price' => 'nullable|numeric|min:0',
            'cost_price' => 'nullable|numeric|min:0',
            'unit_label' => 'nullable|string|max:40',
            'source_binding' => ['nullable', Rule::in(AccCardCategory::BINDINGS)],
            'card_category_id' => 'nullable|integer',
            'sort_order' => 'nullable|integer|min:0',
            'is_active' => 'nullable|boolean',
        ]);
    }

    private function serialize(AccCardCategory $c): array
    {
        return [
            'id' => $c->id,
            'name' => $c->name,
            'sell_price' => (float) $c->sell_price,
            'cost_price' => (float) $c->cost_price,
            'unit_label' => $c->unit_label,
            'source_binding' => $c->source_binding,
            'card_category_id' => $c->card_category_id,
            'sort_order' => $c->sort_order,
            'is_active' => $c->is_active,
            'stock_qty' => (float) ($c->stock->qty ?? 0),
            'avg_cost' => (float) ($c->stock->avg_cost ?? 0),
        ];
    }

    private function audit(AccContext $ctx, string $action, int $entityId, array $meta): void
    {
        AccAuditLog::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'action' => $action,
            'entity' => 'acc_card_categories',
            'entity_id' => $entityId,
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }
}
