<?php

namespace App\Services;

use App\Models\Transaction;
use App\Models\User;
use App\Models\WalletLog;

/**
 * Centralizes the "سلفني" (advance) repayment logic so it behaves
 * identically wherever a customer's advance debt can be settled (currently:
 * approving a wallet top-up). Keeping this in one place guarantees the
 * advance mechanism never interferes with normal balance/profit accounting.
 *
 * Rules implemented here:
 *  - Repayment is deducted from a top-up BEFORE any amount is credited to
 *    the customer's spendable balance.
 *  - If the top-up is smaller than the outstanding advance, the whole
 *    top-up is applied as a partial repayment (no balance is credited).
 *  - Advances are settled oldest-first (FIFO) across possibly multiple
 *    outstanding advance transactions.
 *  - The network owner's commission/profit for an advance transaction is
 *    only realized once that specific transaction is fully repaid, so an
 *    unpaid advance never shows up as (or distorts) profit.
 */
class AdvanceService
{
    /**
     * Apply `$amount` (a just-approved top-up) to the user's outstanding
     * advance debt first, then return how much is left to credit as normal
     * spendable balance.
     *
     * @return array{repaid: float, remainder: float}
     */
    public function settleFromTopup(User $user, float $amount): array
    {
        $outstanding = (float) $user->advance_balance;

        if ($outstanding <= 0 || $amount <= 0) {
            return ['repaid' => 0.0, 'remainder' => $amount];
        }

        $repayable = min($amount, $outstanding);
        $remaining = $repayable;

        $advances = Transaction::outstandingAdvances()
            ->where('user_id', $user->id)
            ->lockForUpdate()
            ->orderBy('created_at')
            ->get();

        foreach ($advances as $advance) {
            if ($remaining <= 0) {
                break;
            }

            $owed = (float) $advance->total_amount - (float) $advance->repaid_amount;
            if ($owed <= 0) {
                continue;
            }

            $applied = min($owed, $remaining);
            $newRepaid = round((float) $advance->repaid_amount + $applied, 2);
            $isFullySettled = $newRepaid >= (float) $advance->total_amount - 0.001;

            $advance->update([
                'repaid_amount' => $newRepaid,
                'advance_status' => $isFullySettled ? 'repaid' : 'partially_repaid',
                'repaid_at' => $isFullySettled ? now() : $advance->repaid_at,
            ]);

            if ($isFullySettled) {
                $this->recognizeProfit($advance);
            }

            $remaining = round($remaining - $applied, 2);
        }

        $user->decrement('advance_balance', $repayable);

        if ($repayable > 0) {
            WalletLog::create([
                'user_id' => $user->id,
                'type' => 'debit',
                'amount' => $repayable,
                'balance_before' => (float) $user->balance,
                'balance_after' => (float) $user->balance,
                'description' => 'سداد سلفة "سلفني" من مبلغ الشحن',
                'reference_type' => 'advance_settlement',
            ]);
        }

        return ['repaid' => $repayable, 'remainder' => round($amount - $repayable, 2)];
    }

    /**
     * Only now — at full repayment — does the network owner actually get
     * paid their share, and only now is a referral commission generated.
     * This is what keeps an outstanding/unpaid advance from ever affecting
     * profit calculations.
     */
    private function recognizeProfit(Transaction $advance): void
    {
        $network = $advance->network;
        $owner = $network?->owner;

        if ($owner && (float) $advance->network_owner_amount > 0) {
            $owner->increment('available_balance', (float) $advance->network_owner_amount);
        }

        if ($network) {
            $network->recalculateAdvanceSupport();
        }

        // Free up the network's advance pool now that this card slot is repaid.
        $advance->category?->decrement('advance_used_count', min((int) $advance->quantity, (int) $advance->category->advance_used_count));

        if ($advance->user?->referred_by) {
            $referralSetting = \App\Models\CommissionSetting::where('is_active', true)->first();
            $referralPercent = $referralSetting?->commission_percent ?? 1;
            $referralAmount = round((float) $advance->total_amount * ($referralPercent / 100), 2);
            if ($referralAmount > 0) {
                \App\Models\Referral::create([
                    'referrer_id' => $advance->user->referred_by,
                    'referred_id' => $advance->user_id,
                    'transaction_id' => $advance->id,
                    'commission_amount' => $referralAmount,
                    'commission_percentage' => $referralPercent,
                    'is_paid' => false,
                ]);
            }
        }

        try {
            if ($owner) {
                app(NotificationService::class)->send(
                    $owner,
                    'تم سداد سلفة على شبكتك',
                    'تم سداد سلفة بقيمة ' . number_format((float) $advance->total_amount) . ' ريال على شبكتك ' . ($network->name ?? '') . ' وتمت إضافة أرباحك.',
                    ['type' => 'advance_repaid', 'transaction_id' => $advance->id]
                );
            }
        } catch (\Throwable $e) {
            \Log::warning('Advance repayment notification failed: ' . $e->getMessage());
        }
    }
}
