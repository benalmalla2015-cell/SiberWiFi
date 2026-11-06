<?php

namespace App\Console\Commands;

use App\Services\CyberRadiusService;
use Illuminate\Console\Command;

/**
 * cyber:disconnect-due — the CyberNet cut-off engine (CYB-04).
 *
 * Marks expired (time) / exhausted (data) subscriptions ended and
 * sends CoA Disconnect to every session still open on a NAS.
 *
 * Auto-registered from app/Console/Commands (Laravel default path —
 * no shared file touched). Wire the cadence at deploy time with
 * either a crontab line:
 *     * * * * * cd backend && php artisan cyber:disconnect-due
 * or one line in routes/console.php (shared file — left for the
 * orchestrator to merge):
 *     Schedule::command('cyber:disconnect-due')->everyMinute();
 */
class CyberDisconnectDueCommand extends Command
{
    protected $signature = 'cyber:disconnect-due';

    protected $description = 'End due CyberNet subscriptions and send CoA Disconnect to their NAS sessions';

    public function handle(CyberRadiusService $radius): int
    {
        $stats = $radius->disconnectDue();

        $this->info(sprintf(
            'ended=%d coa_sent=%d coa_failed=%d',
            $stats['ended'],
            $stats['coa_sent'],
            $stats['coa_failed']
        ));

        return self::SUCCESS;
    }
}
