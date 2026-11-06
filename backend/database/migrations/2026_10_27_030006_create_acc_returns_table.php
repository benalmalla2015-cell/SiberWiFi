<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Returns register (PLAN §2.1): cards coming back to stock from
     * a sale/POS or going back out to a supplier. The stock movement
     * direction follows `kind`; the journal leg lands with ACC-05.
     */
    public function up(): void
    {
        Schema::create('acc_returns', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('kind', 20); // purchase_return|sale_return|card_return
            $table->string('ref_type', 32)->nullable(); // e.g. acc_purchases, acc_pos_orders
            $table->unsignedBigInteger('ref_id')->nullable();
            $table->foreignId('category_id')
                ->nullable()
                ->constrained('acc_card_categories')
                ->nullOnDelete();
            $table->decimal('qty', 15, 2)->default(0);
            $table->decimal('amount', 15, 2)->default(0);
            $table->string('reason')->nullable();
            $table->date('date');
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->timestamps();

            $table->index(['network_owner_id', 'date'], 'acc_returns_owner_date');
            $table->index(['network_owner_id', 'kind'], 'acc_returns_owner_kind');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_returns');
    }
};
