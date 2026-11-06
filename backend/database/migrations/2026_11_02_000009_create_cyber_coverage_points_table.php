<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet coverage map points (CYB-08) — one row per live CyberNet
     * signal the client app draws on its map. `host_name` links a point
     * to the host serving it (the NAS identifier / host label), `name`
     * is the neighbourhood label shown to subscribers.
     *
     * Status: active (broadcasting) | planned (coming soon) | offline.
     */
    public function up(): void
    {
        Schema::create('cyber_coverage_points', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('city')->nullable();
            $table->string('host_name')->nullable();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->enum('status', ['active', 'planned', 'offline'])
                ->default('active');
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['status', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_coverage_points');
    }
};
