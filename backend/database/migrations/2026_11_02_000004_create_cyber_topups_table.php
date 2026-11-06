<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet top-ups (CYB-04) — agent credits a subscriber by SIM
     * number. `idempotency_key` is unique: an agent retry on the same
     * key returns the original record without re-crediting.
     * `sim_no`/`subscriber_id` are both stored so the ledger stays
     * auditable even if the subscriber row changes.
     */
    public function up(): void
    {
        Schema::create('cyber_topups', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('agent_id')->index();
            $table->unsignedBigInteger('subscriber_id')->index();
            $table->string('sim_no', 16)->index();
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
        Schema::dropIfExists('cyber_topups');
    }
};
