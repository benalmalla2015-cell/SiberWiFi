<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('wallet_logs', function (Blueprint $table) {
            if (!Schema::hasColumn('wallet_logs', 'counterparty_user_id')) {
                $table->foreignId('counterparty_user_id')->nullable()->after('reference_id')->constrained('users')->nullOnDelete();
            }
        });
    }

    public function down(): void
    {
        Schema::table('wallet_logs', function (Blueprint $table) {
            $table->dropColumn(['counterparty_user_id']);
        });
    }
};