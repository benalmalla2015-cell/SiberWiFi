<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "سلفني" (advance / card-lending) fields for card categories.
 * These columns already exist on the live production database from an
 * earlier iteration; this migration documents them for local/dev/staging
 * environments and is safe to run multiple times (guarded by hasColumn).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('card_categories', function (Blueprint $table) {
            if (!Schema::hasColumn('card_categories', 'advance_enabled')) {
                $table->boolean('advance_enabled')->default(false)->after('is_active');
            }
            if (!Schema::hasColumn('card_categories', 'advance_max_cards')) {
                $table->unsignedInteger('advance_max_cards')->default(0)->after('advance_enabled');
            }
            if (!Schema::hasColumn('card_categories', 'advance_max_per_customer')) {
                $table->unsignedInteger('advance_max_per_customer')->nullable()->after('advance_max_cards');
            }
            if (!Schema::hasColumn('card_categories', 'advance_used_count')) {
                $table->unsignedInteger('advance_used_count')->default(0)->after('advance_max_per_customer');
            }
            if (!Schema::hasColumn('card_categories', 'advance_status')) {
                $table->string('advance_status')->default('none')->after('advance_used_count');
            }
            if (!Schema::hasColumn('card_categories', 'advance_requested_at')) {
                $table->timestamp('advance_requested_at')->nullable()->after('advance_status');
            }
            if (!Schema::hasColumn('card_categories', 'advance_approved_at')) {
                $table->timestamp('advance_approved_at')->nullable()->after('advance_requested_at');
            }
            if (!Schema::hasColumn('card_categories', 'advance_approved_by')) {
                $table->unsignedBigInteger('advance_approved_by')->nullable()->after('advance_approved_at');
            }
            if (!Schema::hasColumn('card_categories', 'advance_rejection_reason')) {
                $table->string('advance_rejection_reason', 500)->nullable()->after('advance_approved_by');
            }
        });
    }

    public function down(): void
    {
        Schema::table('card_categories', function (Blueprint $table) {
            foreach ([
                'advance_rejection_reason', 'advance_approved_by', 'advance_approved_at',
                'advance_requested_at', 'advance_status', 'advance_used_count',
                'advance_max_per_customer', 'advance_max_cards', 'advance_enabled',
            ] as $column) {
                if (Schema::hasColumn('card_categories', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
