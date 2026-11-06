<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet subscriber-to-subscriber balance transfers (CYB-06).
     * `idempotency_key` is unique: a retried send returns the original
     * record without re-moving balance. Both sim numbers are stored
     * alongside the subscriber ids so the ledger stays auditable even
     * if a subscriber row changes.
     */
    public function up(): void
    {
        Schema::create('cyber_transfers', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('from_subscriber_id')->index();
            $table->unsignedBigInteger('to_subscriber_id')->index();
            $table->string('from_sim_no', 16)->index();
            $table->string('to_sim_no', 16)->index();
            $table->decimal('amount', 14, 2);
            $table->char('currency', 3)->default('YER');
            $table->enum('status', ['completed', 'failed', 'reversed'])
                ->default('completed');
            $table->string('idempotency_key')->unique();
            $table->json('meta')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_transfers');
    }
};
