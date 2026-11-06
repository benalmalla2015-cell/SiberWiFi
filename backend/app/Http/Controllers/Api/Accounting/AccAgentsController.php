<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\User;
use App\Services\AccContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * CRUD for operating sub-accounts (PLAN §1): admin | distributor |
 * pos. Each row binds an existing `users` account — employees keep
 * using the same login, the agent role picks their UI surface.
 */
class AccAgentsController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccAgent::with('user:id,name,phone')
            ->where('network_owner_id', $ctx->ownerId)
            ->latest();

        if ($role = $request->query('role')) {
            $query->where('role', $role);
        }
        if ($status = $request->query('status')) {
            $query->where('status', $status);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccAgent $a) => $this->serialize($a)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $data = $request->validate([
            'phone' => 'required_without:user_id|string|max:32',
            'user_id' => 'nullable|integer',
            'display_name' => 'required|string|max:190',
            'role' => ['required', Rule::in(AccAgent::ROLES)],
            'agent_phone' => 'nullable|string|max:32',
            'daily_limit_per_category' => 'nullable',
            'cash_allowed' => 'nullable|boolean',
            'credit_allowed' => 'nullable|boolean',
            'status' => ['nullable', Rule::in([AccAgent::STATUS_ACTIVE, AccAgent::STATUS_SUSPENDED])],
            'commission_mode' => ['nullable', Rule::in(AccAgent::COMMISSION_MODES)],
            'commission_value' => 'nullable|numeric|min:0',
        ]);

        $user = isset($data['user_id'])
            ? User::find($data['user_id'])
            : $this->findUserByPhone((string) $data['phone']);

        if ($user === null) {
            return $this->fail('لا يوجد حساب مستخدم بهذا الرقم — يجب أن يسجّل الموظف في التطبيق أولاً', 422);
        }
        if ($user->id === $ctx->ownerId) {
            return $this->fail('حساب المالك لا يحتاج ملف وكيل — يملك كل الصلاحيات', 422);
        }
        if (AccAgent::where('user_id', $user->id)->exists()) {
            return $this->fail('هذا المستخدم مرتبط بحساب وكيل بالفعل', 422);
        }

        $agent = AccAgent::create([
            'network_owner_id' => $ctx->ownerId,
            'user_id' => $user->id,
            'role' => $data['role'],
            'display_name' => $data['display_name'],
            'phone' => $data['agent_phone'] ?? $user->phone ?? $data['phone'] ?? null,
            'daily_limit_per_category' => $this->parseLimits($data['daily_limit_per_category'] ?? null),
            'cash_allowed' => (bool) ($data['cash_allowed'] ?? true),
            'credit_allowed' => (bool) ($data['credit_allowed'] ?? false),
            'status' => $data['status'] ?? AccAgent::STATUS_ACTIVE,
            'commission_mode' => $data['commission_mode'] ?? null,
            'commission_value' => $data['commission_value'] ?? null,
        ]);

        $this->audit($ctx, 'agent.create', $agent->id, ['role' => $agent->role, 'user_id' => $user->id]);

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء حساب الوكيل',
            'data' => $this->serialize($agent->load('user:id,name,phone')),
        ], 201);
    }

    public function update(Request $request, int $agent): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccAgent::where('network_owner_id', $ctx->ownerId)->findOrFail($agent);

        $data = $request->validate([
            'display_name' => 'sometimes|string|max:190',
            'role' => ['sometimes', Rule::in(AccAgent::ROLES)],
            'agent_phone' => 'nullable|string|max:32',
            'daily_limit_per_category' => 'nullable',
            'cash_allowed' => 'nullable|boolean',
            'credit_allowed' => 'nullable|boolean',
            'status' => ['sometimes', Rule::in([AccAgent::STATUS_ACTIVE, AccAgent::STATUS_SUSPENDED])],
            'commission_mode' => ['nullable', Rule::in(AccAgent::COMMISSION_MODES)],
            'commission_value' => 'nullable|numeric|min:0',
        ]);

        if (array_key_exists('daily_limit_per_category', $data)) {
            $data['daily_limit_per_category'] = $this->parseLimits($data['daily_limit_per_category']);
        }

        $model->update($data);
        $this->audit($ctx, 'agent.update', $model->id, ['fields' => array_keys($data)]);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الوكيل',
            'data' => $this->serialize($model->fresh('user:id,name,phone')),
        ]);
    }

    public function destroy(Request $request, int $agent): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccAgent::where('network_owner_id', $ctx->ownerId)->findOrFail($agent);

        $model->delete(); // acc_pos_points.agent_id unbinds via nullOnDelete
        $this->audit($ctx, 'agent.delete', $agent, ['role' => $model->role, 'user_id' => $model->user_id]);

        return response()->json(['success' => true, 'message' => 'تم حذف الوكيل']);
    }

    // ── Internals ────────────────────────────────────────────────

    private function serialize(AccAgent $a): array
    {
        return [
            'id' => $a->id,
            'user_id' => $a->user_id,
            'user_name' => $a->user?->name,
            'user_phone' => $a->user?->phone,
            'role' => $a->role,
            'display_name' => $a->display_name,
            'phone' => $a->phone,
            'daily_limit_per_category' => $a->daily_limit_per_category,
            'cash_allowed' => $a->cash_allowed,
            'credit_allowed' => $a->credit_allowed,
            'status' => $a->status,
            'commission_mode' => $a->commission_mode,
            'commission_value' => $a->commission_value !== null ? (float) $a->commission_value : null,
            'created_at' => $a->created_at?->toISOString(),
        ];
    }

    /**
     * Employees register with whatever phone form the client app used;
     * try the common Yemeni variants so the owner can type what they
     * know (77xxxxxxx, 0967…, +967…).
     */
    private function findUserByPhone(string $phone): ?User
    {
        $phone = trim($phone);
        $digits = preg_replace('/\D+/', '', $phone) ?? $phone;
        $candidates = array_unique(array_filter([
            $phone,
            $digits,
            '0' . $digits,
            '967' . $digits,
            '+967' . $digits,
            preg_replace('/^(?:\+?967|0)+/', '', $digits),
        ]));

        return User::whereIn('phone', $candidates)->first();
    }

    /**
     * Accepts a JSON string (multipart form) or a decoded map of
     * {category_id: qty}; returns null or a clean int=>float map.
     */
    private function parseLimits(mixed $raw): ?array
    {
        if (is_string($raw) && $raw !== '') {
            $decoded = json_decode($raw, true);
            $raw = is_array($decoded) ? $decoded : null;
        }
        if (! is_array($raw) || $raw === []) {
            return null;
        }

        $clean = [];
        foreach ($raw as $catId => $qty) {
            if (is_numeric($catId) && is_numeric($qty) && $qty >= 0) {
                $clean[(int) $catId] = (float) $qty;
            }
        }

        return $clean === [] ? null : $clean;
    }

    private function audit(AccContext $ctx, string $action, int $entityId, array $meta = []): void
    {
        AccAuditLog::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'action' => $action,
            'entity' => 'acc_agents',
            'entity_id' => $entityId,
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }

    private function fail(string $message, int $status): JsonResponse
    {
        return response()->json(['success' => false, 'message' => $message], $status);
    }
}
