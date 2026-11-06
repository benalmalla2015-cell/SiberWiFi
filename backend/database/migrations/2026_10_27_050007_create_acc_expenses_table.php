<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Daily expenses (PLAN §2.3) — money out of a cash box. Each
     * row posts `Dr expenses / Cr cash box`. `status=void` marks a
     * cancelled expense: the journal stays immutable and a reversal
     * entry restores the box (never a delete).
     */
    public function up(): void
    {
        Schema::create('acc_expenses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('category_id')
                ->nullable()
                ->constrained('acc_expense_categories')
                ->nullOnDelete();
            $table->string('category_name')->nullable();
            $table->decimal('amount', 15, 2);
            $table->string('currency', 10)->default('north');
            $table->decimal('exchange_rate', 18, 6)->default(1);
            $table->decimal('base_amount', 15, 2);
            $table->foreignId('cash_box_id')
                ->constrained('acc_cash_boxes')
                ->cascadeOnDelete();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->foreignId('journal_entry_id')
                ->nullable()
                ->constrained('acc_journal_entries')
                ->nullOnDelete();
            $table->timestamp('incurred_at')->useCurrent();
            $table->string('status', 10)->default('posted'); // posted|void
            $table->string('note')->nullable();
            $table->string('idempotency_key')->nullable();
            $table->timestamps();

            $table->unique('idempotency_key', 'acc_expenses_idem_unique');
            $table->index(['network_owner_id', 'incurred_at'], 'acc_expenses_date');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_expenses');
    }
};
