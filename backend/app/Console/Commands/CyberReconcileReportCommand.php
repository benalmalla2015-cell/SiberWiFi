<?php

namespace App\Console\Commands;

use App\Services\CyberUsageService;
use Illuminate\Console\Command;

/**
 * cyber:reconcile-report — trial accuracy check (CYB-09).
 *
 * For each cyber_subscriptions row, RADIUS-recorded bytes (Σ session
 * octets fed by the engine ledger) must equal what the package was
 * debited (consumed_bytes). Any difference — plus session traffic
 * attributed to no package — is flagged; the command exits FAILURE so
 * it can gate deploys or run on a schedule.
 *
 * Auto-registered from app/Console/Commands (no shared file touched).
 * Optional wiring for a periodic run:
 *     Schedule::command('cyber:reconcile-report')->hourly();
 */
class CyberReconcileReportCommand extends Command
{
    protected $signature = 'cyber:reconcile-report
                            {--sim= : Limit the report to one SIM number (74XXXXXXX)}
                            {--json : Emit the report as JSON instead of a table}';

    protected $description = 'Reconcile RADIUS-recorded session bytes against bytes debited from each CyberNet package';

    public function handle(CyberUsageService $usage): int
    {
        $report = $usage->reconcile($this->option('sim') ?: null);

        if ($this->option('json')) {
            $this->line((string) json_encode(
                $report,
                JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
            ));
        } else {
            $this->printTable($report);
        }

        if (! $report['clean']) {
            $this->error('reconcile found differences');

            return self::FAILURE;
        }

        $this->info('reconcile clean — RADIUS records match billing');

        return self::SUCCESS;
    }

    private function printTable(array $report): void
    {
        $this->info('CyberNet reconcile report — '.$report['generated_at']);
        if ($report['sim_no']) {
            $this->line('sim: '.$report['sim_no']);
        }

        $this->table(
            ['subscription', 'sim_no', 'status', 'consumed', 'sessions', 'diff', 'verdict'],
            array_map(fn (array $r) => [
                $r['subscription_id'],
                $r['sim_no'],
                $r['status'],
                $r['consumed_bytes'],
                $r['sessions_bytes'],
                $r['diff_bytes'],
                $r['result'] === 'ok' ? 'OK' : 'DIFF',
            ], $report['subscriptions'])
        );

        if ($report['unattributed']['bytes'] > 0) {
            $this->warn(sprintf(
                'unattributed session bytes: %d across %d session(s) — RADIUS recorded traffic no package absorbed',
                $report['unattributed']['bytes'],
                $report['unattributed']['sessions']
            ));
        }

        $this->info(sprintf(
            'checked=%d matched=%d mismatched=%d',
            $report['checked'],
            $report['matched'],
            $report['mismatched']
        ));
    }
}
