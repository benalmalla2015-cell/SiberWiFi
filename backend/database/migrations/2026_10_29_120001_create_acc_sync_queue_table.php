<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ACC-12 — the offline sync queue (PLAN §2.5).
     *
     * Two producers write here:
     * - the app, pushing offline-captured ops through POST /sync/push
     *   (keyed by the device-generated client_op_id → replayable);
     * - AccPostingService::queueFailedOp, parking a failed post as
     *   needs_review (client_op_id stays null) until it is retried
     *   or discarded from the sync center.
     *
     * Statuses: pending | sent | needs_review.
     */
    public function up(): void
    {
        Schema::create('acc_sync_queue', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            // Device-generated op id — the push idempotency key.
            $table->string('client_op_id', 64)->nullable();
            // e.g. collection.create | dist.sale | post:{doc_type}
            $table->string('op_type', 60);
            $table->json('payload');
            $table->string('status', 20)->default('pending');
            $table->unsignedInteger('attempts')->default(0);
            $table->text('last_error')->nullable();
            // Resulting entity ids after a successful dispatch.
            $table->json('result')->nullable();
            $table->timestamp('sent_at')->nullable();
            $table->timestamps();

            $table->unique(['network_owner_id', 'client_op_id'], 'acc_sync_owner_op');
            $table->index(['network_owner_id', 'status'], 'acc_sync_owner_status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_sync_queue');
    }
};
