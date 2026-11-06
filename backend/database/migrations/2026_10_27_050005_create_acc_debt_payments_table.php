<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Direct debt settlement rows (PLAN §2.3). Each payment is one
     * atomic bundle: this row + a linked acc_collections record +
     * the collection's journal entry — all inside one transaction.
     */
    public function up(): void
    {
        Schema::create('acc_debt_payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('debt_id')
                ->constrained('acc_debts')
                ->cascadeOnDelete();
            $table->foreignId('collection_id')
                ->nullable()
                ->constrained('acc_collections')
                ->nullOnDelete();
            $table->decimal('amount', 15, 2);
            $table->decimal('base_amount', 15, 2);
            $table->foreignId('cash_box_id')
                ->constrained('acc_cash_boxes')
                ->cascadeOnDelete();
            $table->foreignId('journal_entry_id')
                ->nullable()
                ->constrained('acc_journal_entries')
                ->nullOnDelete();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->timestamp('paid_at')->useCurrent();
            $table->string('note')->nullable();
            $table->timestamps();

            $table->index(['network_owner_id', 'debt_id'], 'acc_debt_payments_debt');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_debt_payments');
    }
};
