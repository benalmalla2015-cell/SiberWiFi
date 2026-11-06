<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccAuditLog;
use App\Models\AccSupplier;
use App\Services\AccContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** CRUD for card/package suppliers (PLAN §2.1). */
class AccSuppliersController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        return response()->json([
            'success' => true,
            'data' => AccSupplier::where('network_owner_id', $ctx->ownerId)
                ->withCount('purchases')
                ->latest()
                ->get()
                ->map(fn (AccSupplier $s) => $this->serialize($s)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'name' => 'required|string|max:190',
            'phone' => 'nullable|string|max:32',
            'note' => 'nullable|string|max:190',
        ]);

        $supplier = AccSupplier::create([
            'network_owner_id' => $ctx->ownerId,
            ...$data,
        ]);
        $this->audit($ctx, 'supplier.create', $supplier->id, ['name' => $supplier->name]);

        return response()->json([
            'success' => true,
            'message' => 'تم إضافة المورد',
            'data' => $this->serialize($supplier),
        ], 201);
    }

    public function update(Request $request, int $supplier): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccSupplier::where('network_owner_id', $ctx->ownerId)->findOrFail($supplier);

        $model->update($request->validate([
            'name' => 'sometimes|string|max:190',
            'phone' => 'nullable|string|max:32',
            'note' => 'nullable|string|max:190',
        ]));
        $this->audit($ctx, 'supplier.update', $model->id, []);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث المورد',
            'data' => $this->serialize($model->fresh()),
        ]);
    }

    public function destroy(Request $request, int $supplier): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccSupplier::where('network_owner_id', $ctx->ownerId)->findOrFail($supplier);

        if ($model->purchases()->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'للمورد مشتريات مسجلة — لا يمكن حذفه',
            ], 422);
        }

        $model->delete();
        $this->audit($ctx, 'supplier.delete', $supplier, ['name' => $model->name]);

        return response()->json(['success' => true, 'message' => 'تم حذف المورد']);
    }

    private function serialize(AccSupplier $s): array
    {
        return [
            'id' => $s->id,
            'name' => $s->name,
            'phone' => $s->phone,
            'note' => $s->note,
            'purchases_count' => $s->purchases_count ?? 0,
        ];
    }

    private function audit(AccContext $ctx, string $action, int $entityId, array $meta): void
    {
        AccAuditLog::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'action' => $action,
            'entity' => 'acc_suppliers',
            'entity_id' => $entityId,
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }
}
