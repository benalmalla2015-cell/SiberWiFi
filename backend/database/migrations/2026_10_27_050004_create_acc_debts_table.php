<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Receivable/payable debts (PLAN §2.3). A row is the settlement
     * tracker — `amount_due` minus `amount_paid` with a status
     * machine open → partial → paid, fed by acc_debt_payments.
     *
     * party_type: pos | distributor | customer | person | supplier.
     * For entity parties (pos/distributor/supplier) `party_id` is the
     * entity id; for named parties (customer/person) it self-
     * references this row's id so acc_balances tracks per-debt.
     * Supplier debts run the opposite direction — we owe them.
     */
    public function up(): void
    {
        Schema::create('acc_debts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('party_type', 20);
            $table->unsignedBigInteger('party_id')->nullable();
            $table->string('party_name');
            $table->string('phone', 30)->nullable();
            $table->decimal('amount_due', 15, 2);
            $table->decimal('amount_paid', 15, 2)->default(0);
            $table->decimal('base_due', 15, 2);
            $table->decimal('base_paid', 15, 2)->default(0);
            $table->string('currency', 10)->default('north');
            $table->decimal('exchange_rate', 18, 6)->default(1);
            $table->string('status', 10)->default('open'); // open|partial|paid
            $table->date('due_date')->nullable();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->foreignId('journal_entry_id')
                ->nullable()
                ->constrained('acc_journal_entries')
                ->nullOnDelete();
            $table->string('note')->nullable();
            $table->timestamps();

            $table->index(['network_owner_id', 'status'], 'acc_debts_status');
            $table->index(['network_owner_id', 'party_type', 'party_id'], 'acc_debts_party');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_debts');
    }
};
