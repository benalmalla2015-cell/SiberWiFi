<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Marks card provenance ('platform' bulk uploads vs 'mikrotik'
     * vouchers generated on the owner's router) and carries the
     * voucher's usage limits in `meta` for future accounting —
     * no change to existing rows or purchase flow.
     */
    public function up(): void
    {
        Schema::table('cards', function (Blueprint $table) {
            $table->string('source', 20)->default('platform')->after('status');
            $table->foreignId('router_id')
                ->nullable()
                ->after('network_id')
                ->constrained('mikrotik_routers')
                ->nullOnDelete();
            $table->json('meta')->nullable()->after('serial');
            $table->index('source');
        });
    }

    public function down(): void
    {
        Schema::table('cards', function (Blueprint $table) {
            $table->dropConstrainedForeignId('router_id');
            $table->dropIndex(['source']);
            $table->dropColumn(['source', 'meta']);
        });
    }
};
