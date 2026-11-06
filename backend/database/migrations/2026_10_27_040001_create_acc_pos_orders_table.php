<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS bundle orders (PLAN §2.2) — a POS point requests card
     * bundles with points; an owner/admin/distributor approves or
     * rejects. Approval is ONE atomic transaction: stock out +
     * points ledger + profit ledger + balanced journal entry.
     *
     * idempotency_key makes order submission replayable; the status
     * machine (pending→approved|rejected) plus the journal's own
     * idempotency key make approval replayable too.
     */
    public function up(): void
    {
        Schema::create('acc_pos_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            // PO-YYYYMMDD-NNNNNN — sequential per owner per day.
            $table->string('order_no', 32);
            $table->foreignId('pos_id')
                ->constrained('acc_pos_points')
                ->cascadeOnDelete();
            // The distributor serving the order (null = owner/admin desk).
            $table->foreignId('distributor_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            // The acc_agents row (role pos) that submitted the request.
            $table->foreignId('requested_by')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->string('status', 10)->default('pending'); // pending|approved|rejected
            $table->decimal('total_amount', 15, 2)->default(0);
            $table->decimal('points_total', 15, 2)->default(0);
            $table->foreignId('approved_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->timestamp('approved_at')->nullable();
            $table->string('reject_reason')->nullable();
            $table->string('note')->nullable();
            $table->string('idempotency_key')->nullable();
            $table->timestamps();

            $table->unique(['network_owner_id', 'order_no'], 'acc_pos_orders_no_unique');
            $table->unique('idempotency_key', 'acc_pos_orders_idem_unique');
            $table->index(['network_owner_id', 'status'], 'acc_pos_orders_status');
            $table->index(['network_owner_id', 'pos_id'], 'acc_pos_orders_pos');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_pos_orders');
    }
};
