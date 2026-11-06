<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Accounting card categories (PLAN §2.1, Sprint ACC-02) — the
     * catalog every POS-order/stock document references. Distinct
     * from the platform `card_categories`: the owner manages their
     * accounting-side sell/cost prices freely.
     *
     * `card_category_id` optionally binds a platform card category so
     * the MikroTik auto-sync knows which acc bucket router-generated
     * cards land in — purely additive, cards stays untouched.
     */
    public function up(): void
    {
        Schema::create('acc_card_categories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('name');
            $table->decimal('sell_price', 15, 2)->default(0);
            $table->decimal('cost_price', 15, 2)->default(0);
            // Display label of one stock unit (كرت / باقة / يوم …).
            $table->string('unit_label', 40)->default('كرت');
            // Which card sources this bucket accepts.
            $table->string('source_binding', 10)->default('any'); // platform|mikrotik|any
            // Link to the platform card_categories row for auto-sync.
            $table->foreignId('card_category_id')
                ->nullable()
                ->constrained('card_categories')
                ->nullOnDelete();
            $table->unsignedInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['network_owner_id', 'is_active'], 'acc_card_cat_owner_active');
            $table->index(['network_owner_id', 'card_category_id'], 'acc_card_cat_owner_platform');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_card_categories');
    }
};
