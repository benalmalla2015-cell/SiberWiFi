<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet «سلفني» credit ledger (CYB-06) — one row per borrow or
     * automatic repay. `outstanding_after` snapshots the debt right
     * after the event for auditability. `idempotency_key` is optional
     * but unique when present (borrow retries do not double-credit);
     * repay events carry the collecting top-up/transfer in `meta`.
     */
    public function up(): void
    {
        Schema::create('cyber_credit_events', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('subscriber_id')->index();
            $table->string('sim_no', 16)->index();
            $table->enum('type', ['borrow', 'repay']);
            $table->decimal('amount', 14, 2);
            $table->decimal('outstanding_after', 14, 2)->default(0);
            $table->string('idempotency_key')->nullable()->unique();
            $table->json('meta')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_credit_events');
    }
};
