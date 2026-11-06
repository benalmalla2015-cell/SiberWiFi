<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Devices bound to a POS point (PLAN §2.2) — the physical
     * terminals a POS agent may operate from. device_uid mirrors the
     * app's DeviceIdentityService fingerprint so a point can restrict
     * sign-in to known hardware (enforced by ACC-07).
     */
    public function up(): void
    {
        Schema::create('acc_pos_devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('pos_point_id')
                ->constrained('acc_pos_points')
                ->cascadeOnDelete();
            $table->string('device_uid')->nullable();
            $table->string('device_name');
            $table->string('model')->nullable();
            $table->foreignId('agent_user_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->timestamp('bound_at')->nullable();
            $table->timestamps();

            $table->unique(
                ['network_owner_id', 'device_uid'],
                'acc_pos_devices_owner_uid'
            );
            $table->index('pos_point_id', 'acc_pos_devices_point');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_pos_devices');
    }
};
