<?php

namespace App\Services;

use App\Models\AccAuditLog;
use App\Models\AccBackup;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

/**
 * ACC-12 — tenant-scoped export/restore of the acc_* schema
 * (PLAN §2.5).
 *
 * Export: every acc_* table's tenant rows land in one signed JSON
 * snapshot (signature + sha256 checksum over the canonical tables
 * payload) stored on the local disk and registered in acc_backups.
 *
 * Restore: a full replace of the tenant's acc_* state inside ONE
 * transaction — FK checks off, children wiped before parents,
 * parents re-inserted before children, and every row force-scoped
 * to the restoring tenant (a snapshot can be re-tenanted on
 * disaster recovery without leaking rows between owners).
 *
 * Journal immutability (PLAN §3) governs the live document cycle;
 * restore is a deliberate disaster-recovery action and is audit-
 * logged itself.
 */
class AccBackupService
{
    public const SIGNATURE = 'saiber-acc-backup';

    public const VERSION = 1;

    /**
     * Export order — parents before children so a restore re-inserts
     * references before the rows that point at them. Any table absent
     * from the schema (later sprints) is skipped by hasTable().
     * acc_backups itself is deliberately excluded.
     */
    public const TABLES = [
        'acc_accounts',
        'acc_agents',
        'acc_pos_points',
        'acc_pos_devices',
        'acc_card_categories',
        'acc_suppliers',
        'acc_cash_boxes',
        'acc_expense_categories',
        'acc_doc_header',
        'acc_posting_map',
        'acc_discount_tiers',
        'acc_webhook_events',
        'acc_journal_entries',
        'acc_journal_lines',
        'acc_balances',
        'acc_stock',
        'acc_stock_movements',
        'acc_purchases',
        'acc_returns',
        'acc_damaged',
        'acc_card_imports',
        'acc_debts',
        'acc_collections',
        'acc_debt_payments',
        'acc_cash_transfers',
        'acc_expenses',
        'acc_pos_orders',
        'acc_pos_order_items',
        'acc_points_ledger',
        'acc_profit_ledger',
        'acc_sales',
        'acc_sale_items',
        'acc_commissions',
        'acc_withdrawals',
        'acc_card_exchanges',
        'acc_sync_queue',
        'acc_audit_log',
    ];

    /** Export the tenant's acc_* rows into a registered snapshot. */
    public function export(AccContext $ctx): AccBackup
    {
        $tables = [];
        $rowsCount = 0;

        foreach (self::TABLES as $table) {
            if (! Schema::hasTable($table)) {
                continue;
            }
            $rows = DB::table($table)
                ->where('network_owner_id', $ctx->ownerId)
                ->orderBy('id')
                ->get()
                ->map(fn ($r) => (array) $r)
                ->all();
            $tables[$table] = $rows;
            $rowsCount += count($rows);
        }

        $payload = [
            'signature' => self::SIGNATURE,
            'version' => self::VERSION,
            'network_owner_id' => $ctx->ownerId,
            'exported_at' => now()->toISOString(),
            'checksum' => hash('sha256', json_encode($tables, JSON_UNESCAPED_UNICODE) ?: ''),
            'tables' => $tables,
        ];

        $json = json_encode($payload, JSON_UNESCAPED_UNICODE);
        $filename = 'acc_backup_' . now()->format('Ymd_His') . '.json';
        $path = 'acc_backups/' . $ctx->ownerId . '/' . $filename;
        Storage::disk('local')->put($path, $json);

        $backup = AccBackup::create([
            'network_owner_id' => $ctx->ownerId,
            'filename' => $filename,
            'size' => strlen((string) $json),
            'tables_count' => count($tables),
            'rows_count' => $rowsCount,
            'checksum' => $payload['checksum'],
            'created_by' => $ctx->user->id,
        ]);

        $this->audit($ctx, 'backup.export', $backup->id, [
            'filename' => $filename,
            'tables' => count($tables),
            'rows' => $rowsCount,
        ]);

        return $backup;
    }

    /**
     * Register an uploaded snapshot file as a restorable backup —
     * same signature/checksum verification as export produced.
     */
    public function import(AccContext $ctx, UploadedFile $file): AccBackup
    {
        $json = file_get_contents($file->getRealPath());
        $payload = $this->decodeSnapshot(is_string($json) ? $json : '');

        $filename = 'acc_import_' . now()->format('Ymd_His') . '.json';
        $path = 'acc_backups/' . $ctx->ownerId . '/' . $filename;
        Storage::disk('local')->put($path, $json);

        $backup = AccBackup::create([
            'network_owner_id' => $ctx->ownerId,
            'filename' => $filename,
            'size' => strlen((string) $json),
            'tables_count' => count($payload['tables']),
            'rows_count' => array_sum(array_map('count', $payload['tables'])),
            'checksum' => $payload['checksum'],
            'created_by' => $ctx->user->id,
        ]);

        $this->audit($ctx, 'backup.import', $backup->id, [
            'filename' => $filename,
            'origin_owner' => $payload['network_owner_id'] ?? null,
        ]);

        return $backup;
    }

    /**
     * Atomically replace the tenant's acc_* state with a snapshot.
     * Rejects tampered files before touching a single row.
     */
    public function restore(AccContext $ctx, AccBackup $backup): array
    {
        abort_unless(
            (int) $backup->network_owner_id === $ctx->ownerId,
            403, 'النسخة لا تخص هذا الحساب'
        );

        $json = Storage::disk('local')->get($backup->storagePath());
        abort_if($json === null, 404, 'ملف النسخة غير موجود على القرص');
        $payload = $this->decodeSnapshot($json);

        // The stored registry checksum and the file's own checksum
        // must agree — a tampered export stops here.
        if (! hash_equals($backup->checksum, (string) $payload['checksum'])) {
            throw new AccOrderException('بصمة النسخة لا تطابق السجل — الملف معدّل أو تالف', 422);
        }

        $tables = $payload['tables'];
        $restored = 0;

        // FK pragmas must run outside the transaction on SQLite;
        // the same call is a session flag on MySQL — one path for both.
        Schema::disableForeignKeyConstraints();
        try {
            DB::transaction(function () use ($ctx, $tables, &$restored) {
                foreach (array_reverse(self::TABLES) as $table) {
                    if (! Schema::hasTable($table)) {
                        continue;
                    }
                    DB::table($table)->where('network_owner_id', $ctx->ownerId)->delete();
                }
                foreach (self::TABLES as $table) {
                    if (! Schema::hasTable($table) || ! isset($tables[$table])) {
                        continue;
                    }
                    foreach ($tables[$table] as $row) {
                        $row = (array) $row;
                        // Original ids are preserved so the restored
                        // graph (entries↔lines, orders↔items…) stays
                        // internally consistent.
                        // Force the tenant scope — a snapshot restores
                        // into the restoring owner, never its origin.
                        $row['network_owner_id'] = $ctx->ownerId;
                        DB::table($table)->insert($row);
                        $restored++;
                    }
                }
            });
        } finally {
            Schema::enableForeignKeyConstraints();
        }

        $this->audit($ctx, 'backup.restore', $backup->id, [
            'filename' => $backup->filename,
            'rows' => $restored,
        ]);

        return ['rows' => $restored];
    }

    /**
     * Parse + verify a snapshot payload. Throws AccOrderException
     * (422) on a malformed or integrity-broken file.
     */
    private function decodeSnapshot(string $json): array
    {
        $payload = json_decode($json, true);
        if (! is_array($payload)
            || ($payload['signature'] ?? null) !== self::SIGNATURE
            || ! is_array($payload['tables'] ?? null)) {
            throw new AccOrderException('الملف ليس نسخة احتياطية صالحة للمحاسبة', 422);
        }
        $checksum = hash('sha256', json_encode($payload['tables'], JSON_UNESCAPED_UNICODE) ?: '');
        if (! hash_equals((string) ($payload['checksum'] ?? ''), $checksum)) {
            throw new AccOrderException('بصمة الملف غير متطابقة — النسخة تالفة أو معدّلة', 422);
        }

        return $payload;
    }

    private function audit(AccContext $ctx, string $action, ?int $backupId, array $meta): void
    {
        try {
            if (! Schema::hasTable('acc_audit_log')) {
                return;
            }
            AccAuditLog::create([
                'network_owner_id' => $ctx->ownerId,
                'agent_id' => $ctx->agentId(),
                'action' => $action,
                'entity' => 'acc_backups',
                'entity_id' => $backupId,
                'meta' => $meta,
                'created_at' => now(),
            ]);
        } catch (\Throwable) {
            // Auditing must never break the backup flow.
        }
    }
}
