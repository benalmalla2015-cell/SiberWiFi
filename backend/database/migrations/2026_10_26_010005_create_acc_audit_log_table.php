<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Append-only audit trail (PLAN §2.5) — every financial action
     * leaves a row with latency + payload hash for the perf report.
     */
    public function up(): void
    {
        Schema::create('acc_audit_log', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->string('action', 60);
            $table->string('entity', 60);
            $table->unsignedBigInteger('entity_id')->nullable();
            // e.g. {latency_ms, payload_hash, lines_count, doc_type}
            $table->json('meta')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['network_owner_id', 'entity', 'entity_id'], 'acc_audit_entity_idx');
            $table->index(['network_owner_id', 'created_at'], 'acc_audit_date_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_audit_log');
    }
};
