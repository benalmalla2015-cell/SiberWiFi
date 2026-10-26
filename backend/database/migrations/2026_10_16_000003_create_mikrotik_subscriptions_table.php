<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('mikrotik_subscriptions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            // Null plan = the free trial subscription.
            $table->foreignId('plan_id')
                ->nullable()
                ->constrained('mikrotik_plans')
                ->nullOnDelete();
            $table->enum('status', ['trial', 'active', 'expired', 'cancelled'])
                ->default('trial');
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();
            // Which manual payment request activated it (if any).
            $table->foreignId('payment_request_id')
                ->nullable()
                ->constrained('mikrotik_payment_requests')
                ->nullOnDelete();
            $table->timestamps();

            $table->index(['user_id', 'status']);
            $table->index('ends_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mikrotik_subscriptions');
    }
};
