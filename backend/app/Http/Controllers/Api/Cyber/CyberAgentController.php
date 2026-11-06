<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Services\CyberAgentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Agent-facing CyberNet endpoints (CYB-07) — all behind
 * auth:sanctum; the authenticated user IS the agent (same trust
 * level as POST /api/cyber/topup in CYB-04).
 */
class CyberAgentController extends Controller
{
    public function __construct(private readonly CyberAgentService $agents) {}

    /**
     * GET /api/cyber/agent/profile — the role gate for the agent
     * section of cyber_client_app: 200 means this sanctum user may
     * top up and earns commissions; also hands the app the live
     * commission percent to display.
     */
    public function profile(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'success' => true,
            'data' => [
                'agent_id' => $user->id,
                'name' => $user->name,
                'phone' => $user->phone,
                'type' => $user->type,
                'commission_percent' => (float) config(
                    'cyber.agent_commission_percent',
                    CyberAgentService::DEFAULT_COMMISSION_PERCENT
                ),
            ],
        ]);
    }

    /**
     * GET /api/cyber/agent/earnings — "أرباحي": totals + commission
     * ledger. Reconciles first so rows are complete even if a top-up
     * event was missed.
     */
    public function earnings(Request $request): JsonResponse
    {
        $agentId = (int) $request->user()->id;
        $this->agents->reconcile($agentId);

        return response()->json([
            'success' => true,
            'data' => [
                'summary' => $this->agents->earningsSummary($agentId),
                'commissions' => $this->agents->commissions(
                    $agentId,
                    (int) $request->query('per_page', 20)
                ),
            ],
        ]);
    }

    /**
     * GET /api/cyber/agent/topups — "سجل عملياتي": the agent's own
     * top-up history, newest first.
     */
    public function topups(Request $request): JsonResponse
    {
        $agentId = (int) $request->user()->id;
        $this->agents->reconcile($agentId);

        return response()->json([
            'success' => true,
            'data' => $this->agents->topups(
                $agentId,
                (int) $request->query('per_page', 20)
            ),
        ]);
    }
}
