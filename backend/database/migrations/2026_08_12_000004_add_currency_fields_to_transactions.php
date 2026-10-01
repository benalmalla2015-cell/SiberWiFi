<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            if (!Schema::hasColumn('transactions', 'network_currency')) {
                $table->string('network_currency', 10)->nullable()->after('total_amount');
            }
            if (!Schema::hasColumn('transactions', 'buyer_currency')) {
                $table->string('buyer_currency', 10)->nullable()->after('network_currency');
            }
            if (!Schema::hasColumn('transactions', 'native_amount')) {
                // Price in the network's own currency, before conversion to the buyer's currency.
                $table->decimal('native_amount', 12, 2)->nullable()->after('buyer_currency');
            }
            if (!Schema::hasColumn('transactions', 'exchange_rate_applied')) {
                $table->decimal('exchange_rate_applied', 10, 4)->nullable()->after('native_amount');
            }
        });
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->dropColumn(['network_currency', 'buyer_currency', 'native_amount', 'exchange_rate_applied']);
        });
    }
};
