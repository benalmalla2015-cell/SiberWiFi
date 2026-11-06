<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Point-of-sale outlets (PLAN §2.2). A point may be bound to an
     * acc_agents row of role `pos` — the account that logs into the
     * POS surface. points_balance / profit_balance are the POS-side
     * ledgers (fed by acc_points_ledger / acc_profit_ledger in later
     * sprints) — distinct from the financial AR in acc_balances.
     */
    public function up(): void
    {
        Schema::create('acc_pos_points', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->string('name');
            $table->string('location')->nullable();
            $table->string('owner_name')->nullable();
            $table->string('phone', 32)->nullable();
            $table->string('status', 10)->default('active'); // active|suspended
            $table->decimal('credit_limit', 15, 2)->default(0);
            $table->decimal('points_balance', 15, 2)->default(0);
            $table->decimal('profit_balance', 15, 2)->default(0);
            $table->timestamps();

            $table->index(['network_owner_id', 'status'], 'acc_pos_owner_status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_pos_points');
    }
};
