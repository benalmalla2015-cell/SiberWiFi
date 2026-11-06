<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Models\CyberSession;
use App\Services\CyberBillingService;
use App\Services\CyberUsageService;
use Illuminate\Http\Request;

/**
 * GET /api/cyber/sessions (CYB-09) — the subscriber's session log.
 *
 * Device-bound like the other subscriber endpoints (CYB-04): sim_no +
 * device_id are resolved against cyber_identities. Each row carries
 * start/end, consumed bytes/GB, and the host (NAS-Identifier) that
 * served the session — live rows and the closed archive come from
 * cyber_active_sessions.
 */
class SessionController extends Controller
{
    public function index(Request $request, CyberBillingService $billing, CyberUsageService $usage)
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'max:16'],
            'device_id' => ['required', 'string', 'max:120'],
            'limit' => ['nullable', 'integer', 'min:1', 'max:500'],
        ]);

        $subscriber = $billing->subscriberByDevice($data['sim_no'], $data['device_id']);
        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        $sessions = $usage->sessionsFor(
            (int) $subscriber->id,
            $subscriber->sim_no,
            (int) ($data['limit'] ?? 50)
        );

        $items = $sessions->map(fn (CyberSession $s) => $this->payload($s, $usage));

        return response()->json([
            'success' => true,
            'data' => [
                'sim_no' => $subscriber->sim_no,
                'sessions' => $items->values(),
                'summary' => [
                    'count' => $items->count(),
                    'active' => $sessions->where('status', 'active')->count(),
                    'total_bytes' => (int) $sessions->sum->total_octets,
                    'total_gb' => $usage->toGb((int) $sessions->sum->total_octets),
                ],
            ],
        ]);
    }

    private function payload(CyberSession $session, CyberUsageService $usage): array
    {
        $end = $session->closed_at ?? $session->last_seen_at;

        return [
            'id' => $session->id,
            'session_id' => $session->session_id,
            'host' => $session->nas_identifier,
            'nas_ip' => $session->nas_ip,
            'status' => $session->status,
            'close_reason' => $session->close_reason,
            'started_at' => $session->started_at?->toIso8601String(),
            'ended_at' => $session->closed_at?->toIso8601String(),
            'last_seen_at' => $session->last_seen_at?->toIso8601String(),
            'duration_seconds' => $session->started_at && $end
                ? (int) max(0, $session->started_at->diffInSeconds($end))
                : null,
            'input_octets' => (int) $session->input_octets,
            'output_octets' => (int) $session->output_octets,
            'total_bytes' => $session->total_octets,
            'total_gb' => $usage->toGb($session->total_octets),
        ];
    }
}
