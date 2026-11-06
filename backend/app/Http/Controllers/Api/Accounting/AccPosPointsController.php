<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\AccPosDevice;
use App\Models\AccPosPoint;
use App\Services\AccContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * POS outlets and their bound devices (PLAN §2.2). Tenant-scoped
 * through AccContext — an agent of owner A can never touch owner
 * B's points because every query is filtered by ctx->ownerId.
 */
class AccPosPointsController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccPosPoint::with('agent:id,display_name,role,status')
            ->withCount('devices')
            ->where('network_owner_id', $ctx->ownerId)
            ->latest();

        if ($status = $request->query('status')) {
            $query->where('status', $status);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccPosPoint $p) => $this->serialize($p)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $this->validatePoint($request);
        $error = $this->assertPosAgent($ctx, $data['agent_id'] ?? null);
        if ($error !== null) {
            return $error;
        }

        $point = AccPosPoint::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $data['agent_id'] ?? null,
            'name' => $data['name'],
            'location' => $data['location'] ?? null,
            'owner_name' => $data['owner_name'] ?? null,
            'phone' => $data['phone'] ?? null,
            'status' => $data['status'] ?? AccPosPoint::STATUS_ACTIVE,
            'credit_limit' => $data['credit_limit'] ?? 0,
        ]);

        $this->audit($ctx, 'pos.create', 'acc_pos_points', $point->id);

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء نقطة البيع',
            'data' => $this->serialize($point->load('agent:id,display_name,role,status')),
        ], 201);
    }

    public function update(Request $request, int $pos): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $point = AccPosPoint::where('network_owner_id', $ctx->ownerId)->findOrFail($pos);

        $data = $this->validatePoint($request, partial: true);
        if (array_key_exists('agent_id', $data)) {
            $error = $this->assertPosAgent($ctx, $data['agent_id']);
            if ($error !== null) {
                return $error;
            }
        }

        $point->update($data);
        $this->audit($ctx, 'pos.update', 'acc_pos_points', $point->id, ['fields' => array_keys($data)]);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث نقطة البيع',
            'data' => $this->serialize($point->fresh('agent:id,display_name,role,status')),
        ]);
    }

    public function destroy(Request $request, int $pos): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $point = AccPosPoint::where('network_owner_id', $ctx->ownerId)->findOrFail($pos);

        $point->delete(); // devices cascade
        $this->audit($ctx, 'pos.delete', 'acc_pos_points', $pos, ['name' => $point->name]);

        return response()->json(['success' => true, 'message' => 'تم حذف نقطة البيع']);
    }

    // ── Devices ──────────────────────────────────────────────────

    public function devices(Request $request, int $pos): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $point = AccPosPoint::where('network_owner_id', $ctx->ownerId)->findOrFail($pos);

        return response()->json([
            'success' => true,
            'data' => $point->devices()->latest()->get()
                ->map(fn (AccPosDevice $d) => $this->serializeDevice($d))
                ->values(),
        ]);
    }

    public function storeDevice(Request $request, int $pos): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $point = AccPosPoint::where('network_owner_id', $ctx->ownerId)->findOrFail($pos);

        $data = $request->validate([
            'device_uid' => 'nullable|string|max:190',
            'device_name' => 'required|string|max:190',
            'model' => 'nullable|string|max:190',
            'agent_user_id' => 'nullable|integer|exists:users,id',
        ]);

        $uid = trim((string) ($data['device_uid'] ?? '')) ?: null;
        if ($uid !== null && AccPosDevice::where('network_owner_id', $ctx->ownerId)
            ->where('device_uid', $uid)->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'هذا الجهاز مرتبط بنقطة بيع أخرى',
            ], 422);
        }

        $device = $point->devices()->create([
            'network_owner_id' => $ctx->ownerId,
            'device_uid' => $uid,
            'device_name' => $data['device_name'],
            'model' => $data['model'] ?? null,
            'agent_user_id' => $data['agent_user_id'] ?? null,
            'bound_at' => now(),
        ]);

        $this->audit($ctx, 'pos.device_bind', 'acc_pos_devices', $device->id, ['pos_id' => $point->id]);

        return response()->json([
            'success' => true,
            'message' => 'تم ربط الجهاز',
            'data' => $this->serializeDevice($device),
        ], 201);
    }

    public function destroyDevice(Request $request, int $pos, int $device): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $point = AccPosPoint::where('network_owner_id', $ctx->ownerId)->findOrFail($pos);
        $model = $point->devices()->where('id', $device)->firstOrFail();

        $model->delete();
        $this->audit($ctx, 'pos.device_unbind', 'acc_pos_devices', $device, ['pos_id' => $point->id]);

        return response()->json(['success' => true, 'message' => 'تم فك ربط الجهاز']);
    }

    // ── Internals ────────────────────────────────────────────────

    private function validatePoint(Request $request, bool $partial = false): array
    {
        return $request->validate([
            'name' => [$partial ? 'sometimes' : 'required', 'string', 'max:190'],
            'location' => 'nullable|string|max:190',
            'owner_name' => 'nullable|string|max:190',
            'phone' => 'nullable|string|max:32',
            'agent_id' => 'nullable|integer',
            'status' => ['sometimes', Rule::in([AccPosPoint::STATUS_ACTIVE, AccPosPoint::STATUS_SUSPENDED])],
            'credit_limit' => 'nullable|numeric|min:0',
        ]);
    }

    /** A point may only be bound to a `pos` agent of this tenant. */
    private function assertPosAgent(AccContext $ctx, ?int $agentId): ?JsonResponse
    {
        if ($agentId === null) {
            return null;
        }
        $ok = AccAgent::where('network_owner_id', $ctx->ownerId)
            ->where('id', $agentId)
            ->where('role', 'pos')
            ->exists();

        return $ok ? null : response()->json([
            'success' => false,
            'message' => 'الوكيل المرتبط يجب أن يكون بدور نقطة بيع',
        ], 422);
    }

    private function serialize(AccPosPoint $p): array
    {
        return [
            'id' => $p->id,
            'name' => $p->name,
            'location' => $p->location,
            'owner_name' => $p->owner_name,
            'phone' => $p->phone,
            'status' => $p->status,
            'agent_id' => $p->agent_id,
            'agent_name' => $p->agent?->display_name,
            'agent_status' => $p->agent?->status,
            'devices_count' => $p->devices_count ?? $p->devices()->count(),
            'credit_limit' => (float) $p->credit_limit,
            'points_balance' => (float) $p->points_balance,
            'profit_balance' => (float) $p->profit_balance,
            'created_at' => $p->created_at?->toISOString(),
        ];
    }

    private function serializeDevice(AccPosDevice $d): array
    {
        return [
            'id' => $d->id,
            'pos_point_id' => $d->pos_point_id,
            'device_uid' => $d->device_uid,
            'device_name' => $d->device_name,
            'model' => $d->model,
            'agent_user_id' => $d->agent_user_id,
            'bound_at' => $d->bound_at?->toISOString(),
        ];
    }

    private function audit(AccContext $ctx, string $action, string $entity, int $entityId, array $meta = []): void
    {
        AccAuditLog::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'action' => $action,
            'entity' => $entity,
            'entity_id' => $entityId,
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }
}
