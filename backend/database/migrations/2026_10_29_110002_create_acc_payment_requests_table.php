<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Manual bank/e-wallet transfer requests for accounting plans
     * (ACC-11, PLAN §6.1) — mirrors mikrotik_payment_requests, keyed
     * by network_owner_id (tenant) instead of a single user so an
     * approved receipt activates the whole tenant. `user_id` keeps
     * the acting submitter for admin review.
     */
    public function up(): void
    {
        Schema::create('acc_payment_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('user_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->foreignId('plan_id')
                ->constrained('acc_plans')
                ->cascadeOnDelete();
            $table->decimal('amount', 12, 2);
            $table->string('sender_name');
            $table->foreignId('bank_account_id')
                ->nullable()
                ->constrained('bank_accounts')
                ->nullOnDelete();
            $table->string('transfer_receipt_number')->nullable();
            $table->string('receipt_image')->nullable();
            $table->enum('status', ['pending', 'approved', 'rejected'])
                ->default('pending');
            $table->text('admin_note')->nullable();
            $table->foreignId('reviewed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamps();

            $table->index(['network_owner_id', 'status']);
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_payment_requests');
    }
};
