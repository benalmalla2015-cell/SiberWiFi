<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('wallet_logs', function (Blueprint $table) {
            if (!Schema::hasColumn('wallet_logs', 'sender_name')) {
                $table->string('sender_name')->nullable()->after('transfer_receipt_number')
                    ->comment('اسم المودع / اسم المرسل');
            }
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('wallet_logs', function (Blueprint $table) {
            if (Schema::hasColumn('wallet_logs', 'sender_name')) {
                $table->dropColumn('sender_name');
            }
        });
    }
};
