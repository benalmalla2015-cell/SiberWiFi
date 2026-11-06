<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Corrective FKs: acc_journal_entries.agent_id and
     * acc_audit_log.agent_id reference acc_agents — the operating
     * sub-account that performed the action — not users.
     *
     * Both ACC-01 tables predate acc_agents (020001), so the wrong
     * inline `users` constraint could not have pointed at the right
     * target anyway; sqlite never enforced it in tests but MySQL
     * rejected the first live post. Dropping is a no-op where the
     * bad constraint never existed (fresh installs now create the
     * columns without it), so the same migration repairs deployed
     * databases and completes new ones.
     */
    public function up(): void
    {
        foreach (['acc_journal_entries', 'acc_audit_log'] as $table) {
            try {
                Schema::table($table, function (Blueprint $t) {
                    $t->dropForeign(['agent_id']);
                });
            } catch (\Throwable) {
                // Constraint absent (fresh install or sqlite).
            }

            Schema::table($table, function (Blueprint $t) {
                $t->foreign('agent_id')
                    ->references('id')
                    ->on('acc_agents')
                    ->nullOnDelete();
            });
        }
    }

    public function down(): void
    {
        foreach (['acc_journal_entries', 'acc_audit_log'] as $table) {
            try {
                Schema::table($table, function (Blueprint $t) {
                    $t->dropForeign(['agent_id']);
                });
            } catch (\Throwable) {
            }
        }
    }
};
