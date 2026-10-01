<?php

require_once __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

use App\Models\Referral;
use App\Models\User;
use App\Models\WalletLog;
use Illuminate\Support\Facades\DB;

echo "Starting referral data correction...\n";

DB::transaction(function () {
    $rows = Referral::with('transaction')
        ->whereNotNull('transaction_id')
        ->get();

    foreach ($rows as $referral) {
        $buyerId = $referral->transaction?->user_id;
        if (!$buyerId) {
            echo "Skipping referral {$referral->id}: no transaction buyer.\n";
            continue;
        }

        $needsSwap = (int) $referral->referrer_id !== (int) $buyerId;
        $oldReferrerId = $referral->referrer_id;

        if ($needsSwap) {
            $referral->referred_id = $oldReferrerId;
            $referral->referrer_id = $buyerId;
        }

        if ($referral->is_paid && $needsSwap) {
            $oldUser = User::lockForUpdate()->find($oldReferrerId);
            $buyer = User::lockForUpdate()->find($buyerId);

            if ($oldUser && $buyer) {
                $amount = (float) $referral->commission_amount;

                // Reverse incorrect credit from old referrer
                $oldBalanceBefore = (float) $oldUser->balance;
                $oldUser->decrement('balance', $amount);
                $oldUser->decrement('available_balance', $amount);
                $oldUser->refresh();

                WalletLog::create([
                    'user_id' => $oldUser->id,
                    'type' => 'debit',
                    'amount' => $amount,
                    'balance_before' => $oldBalanceBefore,
                    'balance_after' => (float) $oldUser->balance,
                    'description' => 'إعادة صرف عمولة إحالية خاطئة للمشتري (تصحيح)',
                    'reference_type' => 'referral_payout_reversal',
                    'reference_id' => $referral->id,
                ]);

                // Apply correct credit to buyer
                $buyerBalanceBefore = (float) $buyer->balance;
                $buyer->increment('balance', $amount);
                $buyer->increment('available_balance', $amount);
                $buyer->refresh();

                WalletLog::create([
                    'user_id' => $buyer->id,
                    'type' => 'referral_commission',
                    'amount' => $amount,
                    'balance_before' => $buyerBalanceBefore,
                    'balance_after' => (float) $buyer->balance,
                    'description' => 'صرف عمولة إحالة - عملية شراء رقم ' . ($referral->transaction?->transaction_number ?? $referral->id),
                    'reference_type' => 'referral_payout',
                    'reference_id' => $referral->id,
                ]);

                echo "Corrected paid referral {$referral->id}: moved {$amount} from user {$oldReferrerId} to buyer {$buyerId}\n";
            } else {
                echo "Could not find users for paid referral {$referral->id}\n";
            }
        } elseif ($needsSwap) {
            echo "Swapped unpaid referral {$referral->id}: buyer {$buyerId} is now referrer.\n";
        } else {
            echo "Referral {$referral->id} already correct.\n";
        }

        $referral->save();
    }
});

echo "Done.\n";
