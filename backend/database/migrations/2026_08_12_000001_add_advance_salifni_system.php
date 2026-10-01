<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Outstanding "Salifni" (advance) debt owed by the customer, and
        // convenience total for reporting on how much advance was ever used.
        Schema::table('users', function (Blueprint $table) {
            if (!Schema::hasColumn('users', 'advance_balance')) {
                $table->decimal('advance_balance', 12, 2)->default(0)->after('frozen_balance');
            }
        });

        // Per-network / per-category advance ("سلفني") configuration.
        // Network owners request it; admin must approve before it becomes
        // visible/usable in the customer app.
        Schema::table('card_categories', function (Blueprint $table) {
            if (!Schema::hasColumn('card_categories', 'advance_enabled')) {
                $table->boolean('advance_enabled')->default(false)->after('is_active');
            }
            if (!Schema::hasColumn('card_categories', 'advance_max_cards')) {
                $table->unsignedInteger('advance_max_cards')->default(0)->after('advance_enabled');
            }
            if (!Schema::hasColumn('card_categories', 'advance_used_count')) {
                $table->unsignedInteger('advance_used_count')->default(0)->after('advance_max_cards');
            }
            if (!Schema::hasColumn('card_categories', 'advance_status')) {
                // none | pending | approved | rejected
                $table->string('advance_status')->default('none')->after('advance_used_count');
            }
            if (!Schema::hasColumn('card_categories', 'advance_requested_at')) {
                $table->timestamp('advance_requested_at')->nullable()->after('advance_status');
            }
            if (!Schema::hasColumn('card_categories', 'advance_approved_at')) {
                $table->timestamp('advance_approved_at')->nullable()->after('advance_requested_at');
            }
            if (!Schema::hasColumn('card_categories', 'advance_approved_by')) {
                $table->foreignId('advance_approved_by')->nullable()->constrained('users')->nullOnDelete()->after('advance_approved_at');
            }
            if (!Schema::hasColumn('card_categories', 'advance_rejection_reason')) {
                $table->string('advance_rejection_reason', 500)->nullable()->after('advance_approved_by');
            }
        });

        // Advance ("سلفني") tracking on transactions: the transaction is
        // created immediately when cards are handed out, but the network
        // owner's commission/profit is only realized once the customer
        // repays the advance (see WalletLogResource::approveTopup).
        Schema::table('transactions', function (Blueprint $table) {
            if (!Schema::hasColumn('transactions', 'is_advance')) {
                $table->boolean('is_advance')->default(false)->after('status');
            }
            if (!Schema::hasColumn('transactions', 'advance_status')) {
                // outstanding | partially_repaid | repaid
                $table->string('advance_status')->nullable()->after('is_advance');
            }
            if (!Schema::hasColumn('transactions', 'repaid_amount')) {
                $table->decimal('repaid_amount', 12, 2)->default(0)->after('advance_status');
            }
            if (!Schema::hasColumn('transactions', 'repaid_at')) {
                $table->timestamp('repaid_at')->nullable()->after('repaid_amount');
            }
        });
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->dropColumn(['is_advance', 'advance_status', 'repaid_amount', 'repaid_at']);
        });

        Schema::table('card_categories', function (Blueprint $table) {
            $table->dropConstrainedForeignId('advance_approved_by');
            $table->dropColumn([
                'advance_enabled', 'advance_max_cards', 'advance_used_count',
                'advance_status', 'advance_requested_at', 'advance_approved_at',
                'advance_rejection_reason',
            ]);
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('advance_balance');
        });
    }
};
