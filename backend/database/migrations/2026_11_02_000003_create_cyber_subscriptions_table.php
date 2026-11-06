<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet subscriptions (CYB-04) — subscriber ↔ package window.
     *
     * `radius_reply` caches the RADIUS reply attributes computed at
     * activation (Mikrotik-Rate-Limit, Mikrotik-Total-Limit,
     * Session-Timeout) so the authorize path never re-derives them.
     * `idempotency_key` makes client activation retries safe.
     *
     * Status: active → exhausted (data ran out) | expired (time ran
     * out) | cancelled.
     */
    public function up(): void
    {
        Schema::create('cyber_subscriptions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('subscriber_id')->index();
            $table->unsignedBigInteger('package_id')->index();
            $table->timestamp('starts_at');
            $table->timestamp('ends_at');
            $table->unsignedBigInteger('data_limit_bytes')->nullable();
            $table->unsignedBigInteger('consumed_bytes')->default(0);
            $table->enum('status', ['active', 'exhausted', 'expired', 'cancelled'])
                ->default('active');
            $table->json('radius_reply')->nullable();
            $table->timestamp('ended_at')->nullable();
            $table->string('idempotency_key')->nullable()->unique();
            $table->timestamps();

            $table->index(['status', 'ends_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_subscriptions');
    }
};
