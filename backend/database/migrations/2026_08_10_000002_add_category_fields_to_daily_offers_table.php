<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('daily_offers', function (Blueprint $table) {
            if (!Schema::hasColumn('daily_offers', 'apply_to_all_categories')) {
                $table->boolean('apply_to_all_categories')->default(false)->after('discount_percent');
            }
            if (!Schema::hasColumn('daily_offers', 'category_ids')) {
                $table->json('category_ids')->nullable()->after('apply_to_all_categories');
            }
        });
    }

    public function down(): void
    {
        Schema::table('daily_offers', function (Blueprint $table) {
            $table->dropColumn(['apply_to_all_categories', 'category_ids']);
        });
    }
};
