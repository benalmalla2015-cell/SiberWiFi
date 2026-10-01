<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            if (!Schema::hasColumn('transactions', 'network_currency')) {
                $table->string('network_currency', 20)->nullable()->after('status');
            }
            if (!Schema::hasColumn('transactions', 'buyer_currency')) {
                $table->string('buyer_currency', 20)->nullable()->after('network_currency');
            }
            if (!Schema::hasColumn('transactions', 'native_amount')) {
                $table->decimal('native_amount', 12, 2)->nullable()->after('buyer_currency');
            }
            if (!Schema::hasColumn('transactions', 'exchange_rate_applied')) {
                $table->decimal('exchange_rate_applied', 8, 4)->nullable()->after('native_amount');
            }
        });

        DB::statement("ALTER TABLE transactions MODIFY COLUMN payment_method ENUM('wallet','cash','advance') NOT NULL DEFAULT 'wallet'");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE transactions MODIFY COLUMN payment_method ENUM('wallet','cash') NOT NULL DEFAULT 'wallet'");

        Schema::table('transactions', function (Blueprint $table) {
            $table->dropColumn(['network_currency', 'buyer_currency', 'native_amount', 'exchange_rate_applied']);
        });
    }
};
