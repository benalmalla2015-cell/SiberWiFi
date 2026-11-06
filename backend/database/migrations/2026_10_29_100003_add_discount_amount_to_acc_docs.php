<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ACC-10 — snapshot columns for tier-applied discounts.
     *
     * additive-only per §0.3 rule 1: the direct_percent tier reduces
     * the posted document value; the granted discount is frozen on
     * the row so reports can show gross vs. net without guessing.
     * Services guard every write with Schema::hasColumn() — sprints
     * predating these columns keep running on the older shape.
     */
    public function up(): void
    {
        Schema::table('acc_sales', function (Blueprint $table) {
            if (! Schema::hasColumn('acc_sales', 'discount_amount')) {
                $table->decimal('discount_amount', 15, 2)
                    ->default(0)
                    ->after('total_amount');
            }
        });

        Schema::table('acc_pos_orders', function (Blueprint $table) {
            if (! Schema::hasColumn('acc_pos_orders', 'discount_amount')) {
                $table->decimal('discount_amount', 15, 2)
                    ->default(0)
                    ->after('total_amount');
            }
        });
    }

    public function down(): void
    {
        if (Schema::hasColumn('acc_sales', 'discount_amount')) {
            Schema::table('acc_sales', function (Blueprint $table) {
                $table->dropColumn('discount_amount');
            });
        }
        if (Schema::hasColumn('acc_pos_orders', 'discount_amount')) {
            Schema::table('acc_pos_orders', function (Blueprint $table) {
                $table->dropColumn('discount_amount');
            });
        }
    }
};
