<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet agent commissions (CYB-07) — one ledger row per
     * completed top-up, credited automatically when
     * CyberTopupCompleted fires. `topup_id` is unique so an
     * idempotent retry or a reconciled re-scan can never
     * double-credit the agent. `percent` and `topup_amount` are
     * snapshotted at credit time so a later config change never
     * rewrites history.
     */
    public function up(): void
    {
        Schema::create('cyber_agent_commissions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('agent_id')->index();
            $table->unsignedBigInteger('topup_id')->unique();
            $table->unsignedBigInteger('subscriber_id')->index();
            $table->string('sim_no', 16)->index();
            $table->decimal('topup_amount', 14, 2);
            $table->decimal('percent', 5, 2);
            $table->decimal('amount', 14, 2);
            $table->char('currency', 3)->default('YER');
            $table->enum('status', ['accrued', 'paid_out', 'void'])
                ->default('accrued');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_agent_commissions');
    }
};
