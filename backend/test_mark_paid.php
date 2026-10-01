<?php

require_once __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

use App\Models\Referral;
use App\Models\User;
use App\Models\WalletLog;
use Illuminate\Support\Facades\DB;

$referral = Referral::findOrFail(21);
echo "Before: is_paid=" . ($referral->is_paid ? '1' : '0') . " amount={$referral->commission_amount} beneficiary_id={$referral->referrer_id}\n";

DB::transaction(function () use ($referral) {
    $beneficiary = $referral->referrer;
    if (!$beneficiary) {
        throw new Exception('No beneficiary');
    }

    $referral->update(['is_paid' => true, 'paid_at' => now()]);

    $balanceBefore = (float) $beneficiary->balance;
    $beneficiary->increment('balance', $referral->commission_amount);
    $beneficiary->increment('available_balance', $referral->commission_amount);

    WalletLog::create([
        'user_id' => $beneficiary->id,
        'type' => 'referral_commission',
        'amount' => $referral->commission_amount,
        'balance_before' => $balanceBefore,
        'balance_after' => (float) $beneficiary->fresh()->balance,
        'description' => 'صرف عمولة إحالة - عملية شراء رقم ' . ($referral->transaction?->transaction_number ?? $referral->id),
        'reference_type' => 'referral_payout',
        'reference_id' => $referral->id,
    ]);
});

$referral->refresh();
$user = User::find($referral->referrer_id);
echo "After: is_paid=" . ($referral->is_paid ? '1' : '0') . " balance={$user->balance} available={$user->available_balance}\n";
