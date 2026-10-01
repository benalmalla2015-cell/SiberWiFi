<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Per-customer cap on how many cards a single customer may receive
        // as an advance ("سلفني") for this category. Null = no per-customer
        // cap (only the overall advance_max_cards pool applies).
        Schema::table('card_categories', function (Blueprint $table) {
            if (!Schema::hasColumn('card_categories', 'advance_max_per_customer')) {
                $table->unsignedInteger('advance_max_per_customer')->nullable()->after('advance_max_cards');
            }
        });
    }

    public function down(): void
    {
        Schema::table('card_categories', function (Blueprint $table) {
            $table->dropColumn('advance_max_per_customer');
        });
    }
};
