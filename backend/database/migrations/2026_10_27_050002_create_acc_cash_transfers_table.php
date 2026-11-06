<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Cash transfers between boxes (PLAN §2.3). `amount` leaves the
     * source box in its own currency; `to_amount` arrives at the
     * destination in its currency (equal unless the boxes differ in
     * currency — then `exchange_rate` records the conversion used).
     * The journal entry posts both legs in base currency.
     */
    public function up(): void
    {
        Schema::create('acc_cash_transfers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('from_box_id')
                ->constrained('acc_cash_boxes')
                ->cascadeOnDelete();
            $table->foreignId('to_box_id')
                ->constrained('acc_cash_boxes')
                ->cascadeOnDelete();
            $table->decimal('amount', 15, 2);
            $table->decimal('to_amount', 15, 2);
            $table->string('currency', 10)->default('north');
            $table->decimal('exchange_rate', 18, 6)->default(1);
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->foreignId('journal_entry_id')
                ->nullable()
                ->constrained('acc_journal_entries')
                ->nullOnDelete();
            $table->string('note')->nullable();
            $table->string('idempotency_key')->nullable();
            $table->timestamps();

            $table->unique('idempotency_key', 'acc_cash_transfers_idem_unique');
            $table->index(['network_owner_id', 'created_at'], 'acc_cash_transfers_date');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_cash_transfers');
    }
};
