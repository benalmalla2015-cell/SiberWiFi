<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Profit-balance withdrawal requests (PLAN §2.2, Sprint ACC-07).
     *
     * A POS point (or a distributor — same lifecycle, dist surface
     * lands with ACC-06/10) asks to cash out accumulated profit.
     * The status machine:
     *   pending → approved → paid      (management surface)
     *   pending → rejected             (hold refunded)
     *   pending → cancelled            (requester withdraws it)
     *
     * The profit hold is taken at request time — profit_ledger gets
     * a signed delta and acc_pos_points.profit_balance moves inside
     * the same transaction, so a requester can never double-spend
     * the same accrued profit. Rejection/cancellation posts the
     * inverse delta; `paid` posts the journal entry that moves real
     * cash out of a cash box.
     *
     * (requester_type, requester_id) points at acc_pos_points ('pos')
     * or acc_agents ('distributor') — polymorphic by convention,
     * like acc_profit_ledger.
     */
    public function up(): void
    {
        Schema::create('acc_withdrawals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('requester_type', 12); // pos | distributor
            $table->unsignedBigInteger('requester_id');
            // The acc_agents row that submitted the request.
            $table->foreignId('requested_by')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->decimal('amount', 15, 2);
            // pending | approved | paid | rejected | cancelled
            $table->string('status', 12)->default('pending');
            // Receipt fields — who collected the cash on payout.
            $table->string('receiver_name')->nullable();
            $table->string('receipt_no', 60)->nullable();
            $table->string('note')->nullable();
            $table->string('review_note')->nullable();
            $table->foreignId('reviewed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->foreignId('cash_box_id')
                ->nullable()
                ->constrained('acc_cash_boxes')
                ->nullOnDelete();
            $table->foreignId('journal_entry_id')
                ->nullable()
                ->constrained('acc_journal_entries')
                ->nullOnDelete();
            $table->string('idempotency_key')->nullable();
            $table->timestamps();

            $table->unique('idempotency_key', 'acc_withdrawals_idem_unique');
            $table->index(
                ['network_owner_id', 'requester_type', 'requester_id'],
                'acc_withdrawals_party'
            );
            $table->index(['network_owner_id', 'status'], 'acc_withdrawals_status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_withdrawals');
    }
};
