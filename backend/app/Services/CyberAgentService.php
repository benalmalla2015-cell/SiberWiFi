<?php

namespace App\Services;

use App\Models\CyberAgentCommission;
use App\Models\CyberTopup;
use Illuminate\Database\QueryException;

/**
 * CyberNet agent side of billing (CYB-07).
 *
 * - creditForTopup(): writes one commission row per completed top-up.
 *   The percent is read from config('cyber.agent_commission_percent')
 *   at credit time and snapshotted onto the row. Unique topup_id makes
 *   the write idempotent — retries and re-scans return the existing row.
 * - reconcile(): backfills commission rows for top-ups whose event was
 *   missed (e.g. a listener not registered under route:cache). The
 *   earnings endpoints call it so the ledger is always complete.
 * - earningsSummary()/commissions()/topups(): read models behind the
 *   agent screens ("أرباحي" + "عملياتي").
 */
class CyberAgentService
{
    /** Default percent when the config key is absent. */
    public const DEFAULT_COMMISSION_PERCENT = 5.0;

    /**
     * Credit the agent commission for a completed top-up.
     * Returns the commission row (existing one on a duplicate call),
     * or null when the top-up is not in a commissionable state.
     */
    public function creditForTopup(CyberTopup $topup): ?CyberAgentCommission
    {
        if ($topup->status !== 'completed' || ! $topup->agent_id) {
            return null;
        }

        if ($existing = CyberAgentCommission::where('topup_id', $topup->id)->first()) {
            return $existing;
        }

        $percent = (float) config('cyber.agent_commission_percent', self::DEFAULT_COMMISSION_PERCENT);
        $topupAmount = (float) $topup->amount;

        try {
            return CyberAgentCommission::create([
                'agent_id' => (int) $topup->agent_id,
                'topup_id' => $topup->id,
                'subscriber_id' => $topup->subscriber_id,
                'sim_no' => $topup->sim_no,
                'topup_amount' => $topupAmount,
                'percent' => $percent,
                'amount' => round($topupAmount * $percent / 100, 2),
                'currency' => $topup->currency ?: 'YER',
                'status' => CyberAgentCommission::STATUS_ACCRUED,
            ]);
        } catch (QueryException $e) {
            // Lost the unique topup_id race — the other writer's row wins.
            return CyberAgentCommission::where('topup_id', $topup->id)->first();
        }
    }

    /**
     * Backfill commissions for this agent's completed top-ups that have
     * no ledger row yet. Bounded per call; returns rows credited.
     */
    public function reconcile(int $agentId): int
    {
        $missing = CyberTopup::where('agent_id', $agentId)
            ->where('status', 'completed')
            ->whereNotExists(function ($q) {
                $q->selectRaw('1')
                    ->from('cyber_agent_commissions')
                    ->whereColumn('cyber_agent_commissions.topup_id', 'cyber_topups.id');
            })
            ->latest('id')
            ->limit(200)
            ->get();

        foreach ($missing as $topup) {
            $this->creditForTopup($topup);
        }

        return $missing->count();
    }

    /**
     * Totals behind the "أرباحي" screen.
     *
     * @return array{accrued: string, paid_out: string, count: int, today: string, topup_volume: string}
     */
    public function earningsSummary(int $agentId): array
    {
        $base = fn () => CyberAgentCommission::where('agent_id', $agentId);

        return [
            'accrued' => (string) $base()->where('status', CyberAgentCommission::STATUS_ACCRUED)->sum('amount'),
            'paid_out' => (string) $base()->where('status', CyberAgentCommission::STATUS_PAID_OUT)->sum('amount'),
            'count' => $base()->count(),
            'today' => (string) $base()->whereDate('created_at', today())->sum('amount'),
            'topup_volume' => (string) CyberTopup::where('agent_id', $agentId)
                ->where('status', 'completed')->sum('amount'),
        ];
    }

    /**
     * Commission ledger, newest first.
     */
    public function commissions(int $agentId, int $perPage = 20)
    {
        return CyberAgentCommission::where('agent_id', $agentId)
            ->latest('id')
            ->paginate(max(1, min($perPage, 100)));
    }

    /**
     * The agent's own top-up history ("سجل عملياتي") with its
     * commission attached when present.
     */
    public function topups(int $agentId, int $perPage = 20)
    {
        return CyberTopup::where('agent_id', $agentId)
            ->with('agent:id,name')
            ->latest('id')
            ->paginate(max(1, min($perPage, 100)));
    }
}
