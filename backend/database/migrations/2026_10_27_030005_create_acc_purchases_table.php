<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Card/package purchases from suppliers (PLAN §2.1). A posted
     * purchase writes an `in` stock movement and a `purchase`
     * journal entry in the same transaction (ACC-02 hooks, the
     * financial cycle lands fully in ACC-05).
     */
    public function up(): void
    {
        Schema::create('acc_purchases', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('supplier_id')
                ->nullable()
                ->constrained('acc_suppliers')
                ->nullOnDelete();
            $table->foreignId('category_id')
                ->constrained('acc_card_categories')
                ->restrictOnDelete();
            $table->string('invoice_no', 64)->nullable();
            $table->decimal('qty', 15, 2);
            $table->decimal('unit_price', 15, 2);
            $table->string('currency', 8)->default('YER');
            $table->decimal('exchange_rate', 15, 6)->default(1);
            $table->decimal('total', 15, 2);
            // cash = paid on receipt, credit = owed to the supplier.
            $table->string('payment', 10)->default('cash'); // cash|credit
            $table->date('date');
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->string('note')->nullable();
            $table->timestamps();

            $table->index(['network_owner_id', 'date'], 'acc_purchases_owner_date');
            $table->index(['network_owner_id', 'category_id'], 'acc_purchases_owner_cat');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_purchases');
    }
};
