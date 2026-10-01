<?php

use App\Models\PayoutRequest;
use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payout_requests', function (Blueprint $table) {
            if (!Schema::hasColumn('payout_requests', 'is_frozen')) {
                $table->boolean('is_frozen')->default(false)->after('status');
            }
        });

        // Freeze balances for existing pending/approved requests so users cannot
        // request more than their available balance after this update.
        if (DB::getDriverName() === 'mysql') {
            DB::transaction(function () {
                $pendingStatuses = ['pending', 'approved'];

                PayoutRequest::whereIn('status', $pendingStatuses)
                    ->where('is_frozen', false)
                    ->lockForUpdate()
                    ->get()
                    ->each(function (PayoutRequest $payout) {
                        $user = User::lockForUpdate()->find($payout->user_id);
                        if (!$user) {
                            return;
                        }

                        $amount = (float) $payout->amount;
                        $available = (float) $user->available_balance;

                        // Only freeze if the user actually has enough available balance.
                        // Requests that would overdraw are left unfrozen so they can be
                        // rejected or handled manually by the admin.
                        if ($available >= $amount) {
                            $user->decrement('available_balance', $amount);
                            $user->increment('frozen_balance', $amount);
                            $payout->update(['is_frozen' => true]);
                        }
                    });
            });
        }
    }

    public function down(): void
    {
        Schema::table('payout_requests', function (Blueprint $table) {
            if (Schema::hasColumn('payout_requests', 'is_frozen')) {
                $table->dropColumn('is_frozen');
            }
        });
    }
};
