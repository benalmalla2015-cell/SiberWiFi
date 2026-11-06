<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Sale lines (PLAN §2.2, Sprint ACC-06). Prices are snapshotted
     * at posting time — the row keeps its own numbers even if the
     * catalog changes later (same convention as acc_pos_order_items).
     */
    public function up(): void
    {
        Schema::create('acc_sale_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('sale_id')
                ->constrained('acc_sales')
                ->cascadeOnDelete();
            $table->unsignedBigInteger('category_id')->nullable();
            $table->string('category_name')->nullable();
            $table->unsignedInteger('qty');
            $table->decimal('unit_price', 15, 2)->default(0);
            $table->decimal('unit_cost', 15, 2)->default(0);
            $table->decimal('line_total', 15, 2)->default(0);
            $table->timestamps();

            $table->index('category_id', 'acc_sale_items_cat');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_sale_items');
    }
};
