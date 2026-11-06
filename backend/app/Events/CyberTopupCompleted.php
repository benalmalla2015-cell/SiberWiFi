<?php

namespace App\Events;

use App\Models\CyberTopup;
use Illuminate\Foundation\Events\Dispatchable;

/**
 * Fired after a CyberNet top-up commits (CYB-04). The FCM receipt
 * notification is sent by CyberBillingService itself today because
 * event discovery isn't wired in bootstrap/app.php; once a provider
 * registration point opens, listeners (e.g. CYB-07 agent
 * commissions) should hook here instead of the service.
 */
class CyberTopupCompleted
{
    use Dispatchable;

    public function __construct(
        public readonly CyberTopup $topup,
        public readonly string $balanceAfter,
    ) {}
}
