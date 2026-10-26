<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Idempotent follow-up to 2026_10_15_000002: some databases (staging
 * rebuilt from an older dump, or installs where the earlier migration
 * was marked run on a schema snapshot) can miss source/router_id/meta
 * on `cards`. Add only what is missing — never drops or rewrites data.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('cards', function (Blueprint $table) {
            if (!Schema::hasColumn('cards', 'source')) {
                $table->string('source', 20)->default('platform')->after('status');
            }
            if (!Schema::hasColumn('cards', 'router_id')) {
                $table->foreignId('router_id')
                    ->nullable()
                    ->after('network_id')
                    ->constrained('mikrotik_routers')
                    ->nullOnDelete();
            }
            if (!Schema::hasColumn('cards', 'meta')) {
                $table->json('meta')->nullable()->after('serial');
            }
        });
    }

    public function down(): void
    {
        // Intentionally empty — this migration only repairs missing
        // columns; rolling back must not strip data from healthy DBs.
    }
};
