<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Distributor commission periods (PLAN §2.4, Sprint ACC-06) —
     * one accrued row per distributor per calendar month, fed by
     * dist sales and approved POS orders inside the same atomic
     * transaction as the sale/approval itself.
     *
     * status: accrued → paid (the payout side lands with ACC-10's
     * withdrawal cycle). The unique (owner, distributor, period)
     * index makes accrual a safe atomic upsert.
     */
    public function up(): void
    {
        Schema::create('acc_commissions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('distributor_id')
                ->constrained('acc_agents')
                ->cascadeOnDelete();
            $table->string('period', 7); // YYYY-MM
            $table->decimal('sales_amount', 15, 2)->default(0);
            $table->decimal('commission_amount', 15, 2)->default(0);
            $table->string('status', 10)->default('accrued'); // accrued|paid
            $table->timestamp('paid_at')->nullable();
            $table->unsignedBigInteger('paid_by')->nullable();
            $table->string('note')->nullable();
            $table->timestamps();

            $table->unique(
                ['network_owner_id', 'distributor_id', 'period'],
                'acc_commissions_period_unique'
            );
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_commissions');
    }
};
