<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Services\CyberRadiusService;
use Illuminate\Http\Request;

/**
 * Engine-facing endpoints (CYB-04), authenticated by the shared
 * CYBER_ENGINE_TOKEN bearer token — not sanctum.
 *
 * POST /api/cyber/radius/events    — engine pushes ledger records
 * POST /api/cyber/radius/authorize — RADIUS authorize-time answer
 */
class RadiusController extends Controller
{
    public function events(Request $request, CyberRadiusService $radius)
    {
        $this->guardEngineToken($request);

        $request->validate([
            'events' => ['required', 'array', 'max:500'],
            'events.*.type' => ['required', 'string', 'max:40'],
        ]);

        // validate() only returns declared keys — the raw events keep
        // their attributes/source which billing needs.
        return response()->json([
            'success' => true,
            'data' => $radius->ingestEvents($request->input('events', [])),
        ]);
    }

    public function authorize(Request $request, CyberRadiusService $radius)
    {
        $this->guardEngineToken($request);

        $data = $request->validate([
            'user' => ['required', 'string', 'max:32'],
        ]);

        $reply = $radius->authorize($data['user']);

        return response()->json([
            'success' => $reply !== null,
            'data' => $reply !== null
                ? ['action' => 'accept', 'reply' => $reply]
                : ['action' => 'reject'],
        ], $reply !== null ? 200 : 403);
    }

    private function guardEngineToken(Request $request): void
    {
        $configured = (string) config('cyber.radius.engine_token', '');
        $provided = (string) $request->bearerToken();

        abort_unless(
            $configured !== '' && hash_equals($configured, $provided),
            401
        );
    }
}
