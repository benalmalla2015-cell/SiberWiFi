<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Routers a network owner manages from the Saiber MikroTik app.
     * Purely additive — touches no wallet/transaction/card table.
     */
    public function up(): void
    {
        Schema::create('mikrotik_routers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('network_id')
                ->nullable()
                ->constrained('networks')
                ->nullOnDelete();
            $table->string('name')->nullable();
            $table->string('host');
            $table->unsignedInteger('api_port')->default(8728);
            $table->string('username')->default('admin');
            // Encrypted at rest; only stored so future remote-access
            // relay features can reuse it — never sent back in the API.
            $table->text('api_password')->nullable();
            $table->string('identity')->nullable();
            $table->string('board_name')->nullable();
            $table->string('os_version')->nullable();
            $table->unsignedInteger('hotspot_users_count')->default(0);
            $table->unsignedInteger('hotspot_active_count')->default(0);
            $table->string('uptime')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamps();

            // One logical router = one row per owner — upsert key for sync
            $table->unique(
                ['user_id', 'host', 'api_port', 'username'],
                'mikrotik_routers_owner_host_unique'
            );
            $table->index('last_seen_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mikrotik_routers');
    }
};
