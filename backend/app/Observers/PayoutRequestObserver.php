<?php

namespace App\Observers;

use App\Models\PayoutRequest;
use App\Models\User;
use App\Models\WalletLog;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PayoutRequestObserver
{
    /**
     * Guards against recursive handling when this observer updates the model.
     */
    private static array $processing = [];

    public function updating(PayoutRequest $payout): void
    {
        if (! $payout->exists) {
            return;
        }

        if (in_array($payout->id, self::$processing, true)) {
            return;
        }

        $originalStatus = $payout->getOriginal('status');
        $newStatus = $payout->status;

        if ($originalStatus === $newStatus) {
            return;
        }

        if (
            in_array($originalStatus, ['pending', 'approved'], true) &&
            in_array($newStatus, ['paid_unconfirmed', 'received'], true)
        ) {
            $this->processPayment($payout, $newStatus);

            return;
        }

        if (
            $newStatus === 'rejected' &&
            in_array($originalStatus, ['pending', 'approved', 'paid_unconfirmed', 'received'], true)
        ) {
            $this->processRejection($payout);
        }
    }

    private function processPayment(PayoutRequest $payout, string $newStatus): void
    {
        $requestedAmount = (float) $payout->amount;
        $paidAmount = (float) ($payout->paid_amount ?? 0);

        if ($paidAmount <= 0) {
            $paidAmount = $requestedAmount;
        }

        if ($paidAmount > $requestedAmount) {
            throw ValidationException::withMessages([
                'paid_amount' => 'المبلغ المدفوع لا يمكن أن يتجاوز مبلغ الطلب.',
            ]);
        }

        DB::transaction(function () use ($payout, $requestedAmount, $paidAmount, $newStatus) {
            self::$processing[] = $payout->id;

            try {
                /** @var User $user */
                $user = User::lockForUpdate()->findOrFail($payout->user_id);

                // Avoid duplicate processing if a debit log already exists.
                $alreadyDebited = (float) WalletLog::where('reference_type', 'payout')
                    ->where('reference_id', $payout->id)
                    ->where('type', 'debit')
                    ->sum('amount');

                if ($alreadyDebited < $paidAmount) {
                    if ($payout->is_frozen) {
                        $unpaid = $requestedAmount - $paidAmount;

                        if ($unpaid > 0) {
                            // Release the unpaid portion back to available balance.
                            $user->increment('available_balance', $unpaid);
                            $user->decrement('frozen_balance', $unpaid);
                        }

                        // The requested amount was already reserved in frozen_balance.
                        // Record the actual paid amount leaving the user's wallet.
                        $user->decrement('frozen_balance', $paidAmount);

                        $balanceAfter = (float) $user->available_balance;

                        WalletLog::create([
                            'user_id' => $user->id,
                            'type' => 'debit',
                            'amount' => $paidAmount,
                            'balance_before' => $balanceAfter,
                            'balance_after' => $balanceAfter,
                            'description' => 'صرف طلب سحب رقم ' . ($payout->request_number ?? $payout->id),
                            'reference_type' => 'payout',
                            'reference_id' => $payout->id,
                        ]);
                    } else {
                        // Legacy request that was created before balance freezing was enabled.
                        if ((float) $user->available_balance < $paidAmount) {
                            throw ValidationException::withMessages([
                                'paid_amount' => 'رصيد صاحب الشبكة غير كافٍ لإتمام الصرف.',
                            ]);
                        }

                        $balanceBefore = (float) $user->available_balance;
                        $user->decrement('available_balance', $paidAmount);

                        WalletLog::create([
                            'user_id' => $user->id,
                            'type' => 'debit',
                            'amount' => $paidAmount,
                            'balance_before' => $balanceBefore,
                            'balance_after' => (float) $user->available_balance,
                            'description' => 'صرف طلب سحب رقم ' . ($payout->request_number ?? $payout->id),
                            'reference_type' => 'payout',
                            'reference_id' => $payout->id,
                        ]);
                    }
                }

                // Finalize the payout record attributes that will be persisted by the original save.
                $payout->is_frozen = false;
                $payout->paid_amount = $paidAmount;

                if ($newStatus === 'paid_unconfirmed') {
                    $payout->paid_at = $payout->paid_at ?? now();
                }

                if ($newStatus === 'received') {
                    $payout->received_confirmed_at = $payout->received_confirmed_at ?? now();
                }
            } finally {
                self::$processing = array_diff(self::$processing, [$payout->id]);
            }
        });
    }

    private function processRejection(PayoutRequest $payout): void
    {
        DB::transaction(function () use ($payout) {
            self::$processing[] = $payout->id;

            try {
                /** @var User $user */
                $user = User::lockForUpdate()->findOrFail($payout->user_id);

                if ($payout->is_frozen) {
                    // Release the reserved amount back to available balance.
                    $amount = (float) $payout->amount;
                    $user->increment('available_balance', $amount);
                    $user->decrement('frozen_balance', $amount);
                } else {
                    $originalStatus = $payout->getOriginal('status');

                    // Funds were already deducted from available balance.
                    if (in_array($originalStatus, ['paid_unconfirmed', 'received'], true)) {
                        $paidAmount = (float) ($payout->paid_amount ?? $payout->amount);
                        $balanceBefore = (float) $user->available_balance;
                        $user->increment('available_balance', $paidAmount);

                        WalletLog::create([
                            'user_id' => $user->id,
                            'type' => 'credit',
                            'amount' => $paidAmount,
                            'balance_before' => $balanceBefore,
                            'balance_after' => (float) $user->available_balance,
                            'description' => 'استرجاع مبلغ طلب سحب مرفوض رقم ' . ($payout->request_number ?? $payout->id),
                            'reference_type' => 'payout',
                            'reference_id' => $payout->id,
                        ]);
                    }
                }

                $payout->is_frozen = false;
            } finally {
                self::$processing = array_diff(self::$processing, [$payout->id]);
            }
        });
    }
}
