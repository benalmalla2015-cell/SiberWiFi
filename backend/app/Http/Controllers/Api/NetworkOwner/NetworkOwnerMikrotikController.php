<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\MikrotikRouter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * Network owner's MikroTik routers — registration/sync registry.
 * Read-only inventory for the owner; the router API password is
 * stored encrypted and never returned.
 */
class NetworkOwnerMikrotikController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $routers = MikrotikRouter::where('user_id', $request->user()->id)
            ->with('network:id,name')
            ->latest()
            ->get()
            ->map(fn($r) => $this->resource($r));

        return response()->json(['success' => true, 'data' => $routers]);
    }

    /**
     * Upsert by (user_id, host, api_port, username) — the app calls this
     * every time it connects, keeping identity/board/version/counts fresh.
     */
    public function sync(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'host' => 'required|string|max:255',
            'api_port' => 'required|integer|min:1|max:65535',
            'username' => 'required|string|max:100',
            'api_password' => 'nullable|string|max:255',
            'name' => 'nullable|string|max:255',
            'network_id' => 'nullable|exists:networks,id',
            'identity' => 'nullable|string|max:255',
            'board_name' => 'nullable|string|max:255',
            'os_version' => 'nullable|string|max:255',
            'hotspot_users_count' => 'nullable|integer|min:0',
            'hotspot_active_count' => 'nullable|integer|min:0',
            'uptime' => 'nullable|string|max:50',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        if ($request->filled('network_id')) {
            $networkIds = $request->user()->networks()->pluck('id')->toArray();
            if (!in_array((int) $request->network_id, $networkIds)) {
                return response()->json(['success' => false, 'message' => 'غير مصرح لك بهذه الشبكة'], 403);
            }
        }

        $key = [
            'user_id' => $request->user()->id,
            'host' => $request->host,
            'api_port' => (int) $request->api_port,
            'username' => $request->username,
        ];

        $attrs = $request->only([
            'name', 'network_id', 'identity', 'board_name', 'os_version',
            'hotspot_users_count', 'hotspot_active_count', 'uptime',
        ]);
        if ($request->filled('api_password')) {
            $attrs['api_password'] = $request->api_password;
        }
        $attrs['last_seen_at'] = now();

        $router = MikrotikRouter::updateOrCreate($key, $attrs);

        return response()->json([
            'success' => true,
            'data' => $this->resource($router->fresh('network')),
            'created' => $router->wasRecentlyCreated,
        ]);
    }

    public function destroy(Request $request, int $id): JsonResponse
    {
        $router = MikrotikRouter::where('user_id', $request->user()->id)->findOrFail($id);
        $router->delete();

        return response()->json(['success' => true, 'message' => 'تم حذف الراوتر']);
    }

    private function resource(MikrotikRouter $r): array
    {
        return [
            'id' => $r->id,
            'name' => $r->name,
            'host' => $r->host,
            'api_port' => $r->api_port,
            'username' => $r->username,
            'identity' => $r->identity,
            'board_name' => $r->board_name,
            'os_version' => $r->os_version,
            'network_id' => $r->network_id,
            'network_name' => $r->network?->name,
            'hotspot_users_count' => $r->hotspot_users_count,
            'hotspot_active_count' => $r->hotspot_active_count,
            'uptime' => $r->uptime,
            'last_seen_at' => $r->last_seen_at?->toDateTimeString(),
            'created_at' => $r->created_at->toDateTimeString(),
        ];
    }
}
