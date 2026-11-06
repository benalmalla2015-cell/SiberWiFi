<?php

namespace App\Services;

use App\Models\AccPointsLedger;
use App\Models\AccPosPoint;
use App\Models\AccProfitLedger;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-10 — the write side of discount-tier rewards (PLAN §2.4).
 *
 * Shared by the document cycles (dist sale, POS order approval):
 * credits a POS point's points/profit bonuses inside the caller's
 * own DB transaction, so a failed document rolls the bonus back
 * with it — the ledger never shows a reward for a document that
 * never posted.
 */
class AccTierRewardWriter
{
    /**
     * Credit the POS's bonus points (acc_points_ledger `bonus`) and
     * profit balance (acc_profit_ledger `adjustment`). No-op when
     * the rewards carry nothing or the ledgers don't exist yet.
     */
    public function credit(
        AccContext $ctx,
        AccPosPoint $pos,
        string $refType,
        int $refId,
        string $docNo,
        array $rewards
    ): void {
        $points = (float) ($rewards['points'] ?? 0);
        $profit = (float) ($rewards['profit'] ?? 0);
        if ($points <= 0 && $profit <= 0) {
            return;
        }

        $point = AccPosPoint::where('network_owner_id', $ctx->ownerId)
            ->lockForUpdate()
            ->find($pos->id);
        if ($point === null) {
            return;
        }

        if ($points > 0 && Schema::hasTable('acc_points_ledger')) {
            $point->points_balance = round((float) $point->points_balance + $points, 2);
            $point->save();

            AccPointsLedger::create([
                'network_owner_id' => $ctx->ownerId,
                'pos_id' => $point->id,
                'reason' => 'bonus',
                'delta' => $points,
                'ref_type' => $refType,
                'ref_id' => $refId,
                'agent_id' => $ctx->agentId(),
                'balance_after' => (float) $point->points_balance,
                'note' => 'مكافأة شريحة خصم — ' . $docNo,
                'created_at' => now(),
            ]);
        }

        if ($profit > 0 && Schema::hasTable('acc_profit_ledger')) {
            $point->profit_balance = round((float) $point->profit_balance + $profit, 2);
            $point->save();

            AccProfitLedger::create([
                'network_owner_id' => $ctx->ownerId,
                'party_type' => 'pos',
                'party_id' => $point->id,
                'reason' => 'adjustment',
                'delta' => $profit,
                'ref_type' => $refType,
                'ref_id' => $refId,
                'agent_id' => $ctx->agentId(),
                'note' => 'مكافأة شريحة رصيد أرباح — ' . $docNo,
                'created_at' => now(),
            ]);
        }
    }
}
