<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Per-account feature overrides for both subscription systems.
 *
 * granted_features: keys opened for this account even beyond its
 *   plan/trial state (e.g. a goodwill unlock).
 * revoked_features: keys withheld from this account even while its
 *   subscription is running (e.g. a policy restriction).
 *
 * Guarded with hasColumn — a partial earlier run can't deadlock the
 * migration on shared MySQL (DDL isn't transactional there).
 */
return new class extends Migration
{
    public function up(): void
    {
        foreach (['mikrotik_subscriptions', 'acc_subscriptions'] as $table) {
            if (!Schema::hasTable($table)
                || Schema::hasColumn($table, 'granted_features')) {
                continue;
            }
            Schema::table($table, function (Blueprint $t) {
                $t->json('granted_features')->nullable()->after('ends_at');
                $t->json('revoked_features')->nullable()->after('granted_features');
            });
        }
    }

    public function down(): void
    {
        foreach (['mikrotik_subscriptions', 'acc_subscriptions'] as $table) {
            if (!Schema::hasTable($table)
                || !Schema::hasColumn($table, 'granted_features')) {
                continue;
            }
            Schema::table($table, function (Blueprint $t) {
                $t->dropColumn(['granted_features', 'revoked_features']);
            });
        }
    }
};
