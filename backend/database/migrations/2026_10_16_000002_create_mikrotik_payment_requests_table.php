<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Manual bank/e-wallet transfer requests for MikroTik plans —
     * intentionally a separate table from wallet top-ups so approval
     * of one never touches the other's pipeline.
     */
    public function up(): void
    {
        Schema::create('mikrotik_payment_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('plan_id')
                ->constrained('mikrotik_plans')
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

            $table->index(['user_id', 'status']);
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mikrotik_payment_requests');
    }
};
