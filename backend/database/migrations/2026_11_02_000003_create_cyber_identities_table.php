<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Cryptographic identity bound to a subscriber (CYB-03) — one row per
     * enrolled device. certificate_serial stays null until the CYB-01
     * engine issues the EAP-TLS certificate (status 'pending').
     */
    public function up(): void
    {
        Schema::create('cyber_identities', function (Blueprint $table) {
            $table->id();
            $table->foreignId('subscriber_id')
                ->constrained('cyber_subscribers')
                ->cascadeOnDelete();
            $table->string('certificate_serial')->nullable()->unique();
            $table->string('device_id')->nullable();
            $table->enum('status', ['pending', 'issued', 'active', 'revoked'])
                ->default('pending');
            $table->timestamps();

            $table->index('device_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_identities');
    }
};
