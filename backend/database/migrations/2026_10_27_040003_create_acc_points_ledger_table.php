<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Append-only points ledger for POS outlets (PLAN §2.2). Every
     * movement of acc_pos_points.points_balance is a signed delta
     * row here — never updated, never deleted. Rows are written
     * inside the same DB transaction as the source document.
     */
    public function up(): void
    {
        Schema::create('acc_points_ledger', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('pos_id')
                ->constrained('acc_pos_points')
                ->cascadeOnDelete();
            // order_purchase | conversion | adjustment | bonus
            $table->string('reason', 30);
            // Signed: negative = points spent, positive = credited.
            $table->decimal('delta', 15, 2);
            $table->string('ref_type', 40)->nullable();
            $table->unsignedBigInteger('ref_id')->nullable();
            // The acc_agents row that caused the movement (null = system/owner).
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->decimal('balance_after', 15, 2)->nullable();
            $table->string('note')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['network_owner_id', 'pos_id'], 'acc_points_ledger_pos');
            $table->index(['ref_type', 'ref_id'], 'acc_points_ledger_ref');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_points_ledger');
    }
};
