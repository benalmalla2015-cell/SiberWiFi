<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Referral commission rows are created per purchase/repayment
     * transaction for the same (referrer_id, referred_id) pair, so the
     * pair cannot be unique. Keep a composite index for lookups instead.
     */
    public function up(): void
    {
        // Add the plain composite index first — MySQL refuses to drop the
        // unique index while it is the only index satisfying the FK.
        Schema::table('referrals', function (Blueprint $table) {
            $table->index(['referrer_id', 'referred_id'], 'referrals_pair_index');
        });
        Schema::table('referrals', function (Blueprint $table) {
            $table->dropUnique(['referrer_id', 'referred_id']);
        });
    }

    public function down(): void
    {
        Schema::table('referrals', function (Blueprint $table) {
            $table->unique(['referrer_id', 'referred_id']);
        });
        Schema::table('referrals', function (Blueprint $table) {
            $table->dropIndex('referrals_pair_index');
        });
    }
};
