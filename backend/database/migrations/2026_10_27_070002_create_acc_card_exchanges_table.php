<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Instant card-for-points redemptions (PLAN §2.2, Sprint ACC-07).
     *
     * Unlike acc_pos_orders — which route through a distributor/admin
     * approval — an exchange is a direct, completed-on-write
     * conversion: the POS point's points are spent, owner stock is
     * decremented, and a balanced journal entry posts, all in ONE
     * transaction. `status` stays open for a future review state.
     *
     * points_spent is server-computed (qty × category sell_price —
     * one point equals one base-currency unit); the client never
     * prices the redemption.
     */
    public function up(): void
    {
        Schema::create('acc_card_exchanges', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('pos_id')
                ->constrained('acc_pos_points')
                ->cascadeOnDelete();
            $table->foreignId('category_id')
                ->nullable()
                ->constrained('acc_card_categories')
                ->nullOnDelete();
            // Snapshots — the row stays self-describing if the
            // category is later renamed or deactivated.
            $table->string('category_name');
            $table->unsignedInteger('qty');
            $table->decimal('unit_price', 15, 2);
            $table->decimal('points_spent', 15, 2);
            $table->string('status', 12)->default('completed'); // completed
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

            $table->unique('idempotency_key', 'acc_card_exch_idem_unique');
            $table->index(['network_owner_id', 'pos_id'], 'acc_card_exch_pos');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_card_exchanges');
    }
};
