<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() !== 'mysql') {
            return;
        }

        DB::statement("ALTER TABLE cards MODIFY card_number VARCHAR(255) NULL");
        DB::statement("ALTER TABLE transactions MODIFY unit_price DECIMAL(12, 2) NOT NULL DEFAULT 0");
        DB::statement("ALTER TABLE payout_requests MODIFY requested_amount DECIMAL(12, 2) NULL");
        DB::statement("ALTER TABLE payout_requests MODIFY remaining_amount DECIMAL(12, 2) NOT NULL DEFAULT 0");
        DB::statement("ALTER TABLE payout_requests MODIFY status VARCHAR(50) NOT NULL DEFAULT 'pending'");
        DB::statement("ALTER TABLE reports MODIFY type VARCHAR(100) NULL");
        DB::statement("ALTER TABLE reports MODIFY description TEXT NULL");
        DB::statement("ALTER TABLE reports MODIFY status VARCHAR(50) NOT NULL DEFAULT 'open'");
    }

    public function down(): void
    {
    }
};
