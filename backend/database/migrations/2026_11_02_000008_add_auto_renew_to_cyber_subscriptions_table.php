<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Auto-renew flag on subscriptions (CYB-08) — additive only.
     *
     * When set, the cyber:auto-renew sweep renews the package from the
     * subscriber wallet one day before ends_at. Off by default — the
     * subscriber opts in from the client app.
     */
    public function up(): void
    {
        Schema::table('cyber_subscriptions', function (Blueprint $table) {
            $table->boolean('auto_renew')->default(false)->after('status');
            $table->index(['auto_renew', 'status', 'ends_at'], 'cyber_subs_renew_due_idx');
        });
    }

    public function down(): void
    {
        Schema::table('cyber_subscriptions', function (Blueprint $table) {
            $table->dropIndex('cyber_subs_renew_due_idx');
            $table->dropColumn('auto_renew');
        });
    }
};
