<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Order lines (PLAN §2.2). category_id references the ACC-02
     * acc_card_categories table — deliberately NOT a foreign key so
     * this sprint stays zero-conflict while ACC-02 lands in
     * parallel; name/cost are snapshotted so an approved order keeps
     * its own numbers even if the catalog row changes later.
     */
    public function up(): void
    {
        Schema::create('acc_pos_order_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')
                ->constrained('acc_pos_orders')
                ->cascadeOnDelete();
            $table->unsignedBigInteger('category_id')->nullable();
            $table->string('category_name')->nullable();
            $table->unsignedInteger('qty');
            $table->decimal('unit_price', 15, 2)->default(0);
            $table->decimal('unit_cost', 15, 2)->default(0);
            $table->decimal('line_total', 15, 2)->default(0);
            $table->timestamps();

            $table->index('category_id', 'acc_pos_order_items_cat');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_pos_order_items');
    }
};
