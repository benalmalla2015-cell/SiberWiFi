<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        DB::statement(
            "ALTER TABLE wallet_logs MODIFY COLUMN type ENUM('credit','debit','cashback','referral_commission','refund','freeze','unfreeze','pending_topup','rejected_topup') NOT NULL"
        );
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement(
            "ALTER TABLE wallet_logs MODIFY COLUMN type ENUM('credit','debit','cashback','referral_commission','refund','freeze','unfreeze','pending_topup') NOT NULL"
        );
    }
};
