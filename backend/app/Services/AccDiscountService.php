<?php

namespace App\Services;

use App\Models\AccDiscountTier;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-10 — discount/reward tier resolution (PLAN §2.4).
 *
 * rewards() is a pure read: the calling document cycle
 * (AccDistService::sale, AccPosOrderService::approve) applies the
 * returned effects inside its own atomic transaction — this
 * service never writes ledgers itself, so a mid-transaction
 * failure can never leave a half-applied tier.
 *
 * Bracket rule: an active tier matches when its `basis` total
 * (qty | amount) lands inside [min, max] — NULL max is open-ended.
 * The winning tier per mode is the deepest matching bracket
 * (highest min; ties break on sort_order then id), mirroring
 * محاسب شبكتي's progressive slabs.
 *
 * Reward math (percent → share of the document amount; fixed →
 * flat value):
 *   direct_percent → discount deducted from the document value
 *   points         → bonus points credited to the POS point
 *   profit_balance → bonus profit credited to the POS point
 *   commission     → extra commission added to the distributor's
 *
 * The whole layer is forward-compatible: before
 * acc_discount_tiers exists every reward resolves to zero.
 */
class AccDiscountService
{
    /**
     * Resolve the rewards a document earns.
     *
     * @return array{
     *     discount: float, points: float, profit: float,
     *     commission: float, tiers: array<string, AccDiscountTier>
     * }
     */
    public function rewards(int $ownerId, float $qty, float $amount): array
    {
        $out = [
            'discount' => 0.0,
            'points' => 0.0,
            'profit' => 0.0,
            'commission' => 0.0,
            'tiers' => [],
        ];

        if (! Schema::hasTable('acc_discount_tiers')) {
            return $out;
        }

        foreach (AccDiscountTier::MODES as $mode) {
            $tier = $this->winningTier($ownerId, $mode, $qty, $amount);
            if ($tier === null) {
                continue;
            }

            $reward = $tier->rewardFor($amount);
            if ($reward <= 0) {
                continue;
            }

            $out['tiers'][$mode] = $tier;
            match ($mode) {
                AccDiscountTier::MODE_PERCENT =>
                    $out['discount'] = min($reward, $amount),
                AccDiscountTier::MODE_POINTS =>
                    $out['points'] = $reward,
                AccDiscountTier::MODE_PROFIT =>
                    $out['profit'] = $reward,
                AccDiscountTier::MODE_COMMISSION =>
                    $out['commission'] = $reward,
            };
        }

        return $out;
    }

    /**
     * Every tier whose bracket matches the given document — used by
     * the /discount-tiers/match preview (one row per mode max).
     */
    public function matchPreview(int $ownerId, float $qty, float $amount): array
    {
        $rewards = $this->rewards($ownerId, $qty, $amount);
        $basis = fn (AccDiscountTier $t) => $t->basis === AccDiscountTier::BASIS_QTY ? $qty : $amount;

        return collect($rewards['tiers'])
            ->map(fn (AccDiscountTier $t, string $mode) => [
                'tier_id' => $t->id,
                'mode' => $mode,
                'mode_label' => AccDiscountTier::modeLabel($mode),
                'basis' => $t->basis,
                'basis_value' => $basis($t),
                'reward' => match ($mode) {
                    AccDiscountTier::MODE_PERCENT => $rewards['discount'],
                    AccDiscountTier::MODE_POINTS => $rewards['points'],
                    AccDiscountTier::MODE_PROFIT => $rewards['profit'],
                    default => $rewards['commission'],
                },
                'min' => (float) $t->min,
                'max' => $t->max !== null ? (float) $t->max : null,
                'reward_value' => (float) $t->reward_value,
                'reward_unit' => $t->reward_unit,
            ])
            ->values()
            ->all();
    }

    /**
     * The deepest matching bracket for one mode: highest `min`
     * wins; ties break on sort_order then id so results stay
     * deterministic when brackets overlap.
     */
    public function winningTier(
        int $ownerId,
        string $mode,
        float $qty,
        float $amount
    ): ?AccDiscountTier {
        return AccDiscountTier::where('network_owner_id', $ownerId)
            ->where('mode', $mode)
            ->where('is_active', true)
            ->get()
            ->filter(fn (AccDiscountTier $t) => $t->matches(
                $t->basis === AccDiscountTier::BASIS_QTY ? $qty : $amount
            ))
            ->sortBy([
                ['min', 'desc'],
                ['sort_order', 'asc'],
                ['id', 'asc'],
            ])
            ->first();
    }
}
