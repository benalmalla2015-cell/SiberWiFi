<?php

namespace App\Console\Commands;

use App\Services\CyberAutoRenewService;
use Illuminate\Console\Command;

/**
 * cyber:auto-renew — the CyberNet renewal sweep (CYB-08).
 *
 * Renews auto_renew subscriptions one day before they end, debiting
 * the subscriber wallet through CyberBillingService::activate().
 *
 * Auto-registered from app/Console/Commands (Laravel default path —
 * no shared file touched). Wire the cadence at deploy time with
 * either a crontab line:
 *     0 * * * * cd backend && php artisan cyber:auto-renew
 * or one line in routes/console.php (shared file — left for the
 * orchestrator to merge):
 *     Schedule::command('cyber:auto-renew')->daily();
 */
class CyberAutoRenewCommand extends Command
{
    protected $signature = 'cyber:auto-renew';

    protected $description = 'Renew auto_renew CyberNet subscriptions due within a day, from wallet balance';

    public function handle(CyberAutoRenewService $renewals): int
    {
        $stats = $renewals->renewDue();

        $this->info(sprintf(
            'renewed=%d failed=%d skipped=%d',
            $stats['renewed'],
            $stats['failed'],
            $stats['skipped']
        ));

        return self::SUCCESS;
    }
}
