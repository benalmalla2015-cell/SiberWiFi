<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('wallet_logs', function (Blueprint $table) {
            if (!Schema::hasColumn('wallet_logs', 'receipt_image')) {
                $table->string('receipt_image')->nullable()->after('sender_name');
            }
        });
    }

    public function down(): void
    {
        Schema::table('wallet_logs', function (Blueprint $table) {
            $table->dropColumn('receipt_image');
        });
    }
};
