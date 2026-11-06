<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Running stock balance per category per tenant (PLAN §2.1).
     * Always written inside the same DB transaction as the matching
     * acc_stock_movements row — the movements log is the source of
     * truth, this table is the locked, readable balance.
     */
    public function up(): void
    {
        Schema::create('acc_stock', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('category_id')
                ->constrained('acc_card_categories')
                ->cascadeOnDelete();
            $table->decimal('qty', 15, 2)->default(0);
            // Weighted average cost — recomputed on every `in` movement.
            $table->decimal('avg_cost', 15, 4)->default(0);
            $table->timestamps();

            $table->unique(['network_owner_id', 'category_id'], 'acc_stock_owner_cat');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_stock');
    }
};
