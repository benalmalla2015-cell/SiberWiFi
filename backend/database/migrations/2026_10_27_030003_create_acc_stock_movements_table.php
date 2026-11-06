<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Immutable stock ledger (PLAN §2.1) — rows are never updated or
     * deleted; corrections are new compensating movements.
     *
     * qty is SIGNED: positive = in, negative = out (the convention
     * ACC-04's order_fill hook already writes).
     *
     * The unique (owner, ref_type, ref_id, type) index makes document
     * postings and the MikroTik card sync idempotent — replaying a
     * post can never double-count stock.
     */
    public function up(): void
    {
        Schema::create('acc_stock_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('category_id')
                ->constrained('acc_card_categories')
                ->cascadeOnDelete();
            $table->string('type', 12); // in|out|adjust|sale|return|damaged|order_fill
            $table->decimal('qty', 15, 2);
            $table->decimal('unit_cost', 15, 4)->default(0);
            $table->string('ref_type', 32)->nullable();
            $table->unsignedBigInteger('ref_id')->nullable();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->string('note')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['network_owner_id', 'category_id', 'created_at'], 'acc_stock_mv_owner_cat_date');
            $table->unique(
                ['network_owner_id', 'ref_type', 'ref_id', 'type'],
                'acc_stock_mv_ref_unique'
            );
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_stock_movements');
    }
};
