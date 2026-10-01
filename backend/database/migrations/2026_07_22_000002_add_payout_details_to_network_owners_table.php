<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('network_owners', function (Blueprint $table) {
            $table->string('payout_full_name')->nullable()->after('business_name');
            $table->string('payout_provider')->nullable()->after('payout_full_name');
            $table->string('payout_account_number')->nullable()->after('payout_provider');
        });
    }

    public function down(): void
    {
        Schema::table('network_owners', function (Blueprint $table) {
            $table->dropColumn(['payout_full_name', 'payout_provider', 'payout_account_number']);
        });
    }
};
