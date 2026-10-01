<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('bank_accounts')) {
            Schema::create('bank_accounts', function (Blueprint $table) {
                $table->id();
                $table->string('owner_name')->comment('اسم صاحب الحساب');
                $table->string('bank_name')->comment('اسم الحساب المصرفي / البنك');
                $table->string('account_number')->comment('رقم الحساب');
                $table->boolean('is_active')->default(true);
                $table->unsignedInteger('sort_order')->default(0);
                $table->timestamps();
            });
        }

        Schema::table('wallet_logs', function (Blueprint $table) {
            if (!Schema::hasColumn('wallet_logs', 'bank_account_id')) {
                $table->foreignId('bank_account_id')->nullable()->constrained('bank_accounts')->nullOnDelete()->after('reference_id');
            }
            if (!Schema::hasColumn('wallet_logs', 'transfer_receipt_number')) {
                $table->string('transfer_receipt_number')->nullable()->after('bank_account_id')->comment('رقم الحوالة / رقم سند الإيداع');
            }
        });
    }

    public function down(): void
    {
        Schema::table('wallet_logs', function (Blueprint $table) {
            $table->dropConstrainedForeignId('bank_account_id');
            $table->dropColumn('transfer_receipt_number');
        });

        Schema::dropIfExists('bank_accounts');
    }
};
