<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Accounting subscriptions (ACC-11, PLAN §6.1) — mirrors
     * mikrotik_subscriptions, keyed by network_owner_id so the plan
     * covers the whole tenant (owner + agents) not one login.
     */
    public function up(): void
    {
        Schema::create('acc_subscriptions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            // Null plan = the free trial subscription.
            $table->foreignId('plan_id')
                ->nullable()
                ->constrained('acc_plans')
                ->nullOnDelete();
            $table->enum('status', ['trial', 'active', 'expired', 'cancelled'])
                ->default('trial');
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();
            // Which manual payment request activated it (if any).
            $table->foreignId('payment_request_id')
                ->nullable()
                ->constrained('acc_payment_requests')
                ->nullOnDelete();
            $table->timestamps();

            $table->index(['network_owner_id', 'status']);
            $table->index('ends_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_subscriptions');
    }
};
