<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet live RADIUS sessions (CYB-04) — one row per
     * Acct-Session-Id seen on a NAS, fed by the engine event stream.
     * The disconnect sweep uses nas_ip + session_id to address CoA
     * Disconnect-Requests (port 3799). Octet counters are cumulative
     * per session as reported by interim/stop accounting.
     *
     * Named cyber_active_sessions (not cyber_sessions) so CYB-09 owns
     * the historical session-log table without a collision.
     */
    public function up(): void
    {
        Schema::create('cyber_active_sessions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('subscriber_id')->nullable()->index();
            $table->unsignedBigInteger('subscription_id')->nullable()->index();
            $table->string('sim_no', 16)->nullable()->index();
            $table->string('nas_identifier')->nullable();
            $table->string('nas_ip')->nullable();
            $table->string('session_id');
            $table->timestamp('started_at')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->unsignedBigInteger('input_octets')->default(0);
            $table->unsignedBigInteger('output_octets')->default(0);
            $table->enum('status', ['active', 'closed'])->default('active');
            $table->string('close_reason')->nullable();
            $table->unsignedTinyInteger('coa_attempts')->default(0);
            $table->timestamp('closed_at')->nullable();
            $table->timestamps();

            $table->unique(['nas_identifier', 'session_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_active_sessions');
    }
};
