<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Append-only profit ledger for POS outlets and distributors
     * (PLAN §2.2) — commission accruals, profit withdrawals and
     * adjustments. The (party_type, party_id) pair points at either
     * an acc_pos_points row ('pos') or an acc_agents row
     * ('distributor'); POS party deltas also roll into
     * acc_pos_points.profit_balance inside the same transaction.
     */
    public function up(): void
    {
        Schema::create('acc_profit_ledger', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('party_type', 12); // pos | distributor
            $table->unsignedBigInteger('party_id');
            // sale_commission | withdrawal | adjustment
            $table->string('reason', 30);
            $table->decimal('delta', 15, 2);
            $table->string('ref_type', 40)->nullable();
            $table->unsignedBigInteger('ref_id')->nullable();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->string('note')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(
                ['network_owner_id', 'party_type', 'party_id'],
                'acc_profit_ledger_party'
            );
            $table->index(['ref_type', 'ref_id'], 'acc_profit_ledger_ref');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_profit_ledger');
    }
};
