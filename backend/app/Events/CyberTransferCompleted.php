<?php

namespace App\Events;

use App\Models\CyberTransfer;
use Illuminate\Foundation\Events\Dispatchable;

/**
 * Fired after a CyberNet transfer commits (CYB-06) — mirror of
 * CyberTopupCompleted for future listeners (audit, agent tooling).
 * Event discovery is still unwired; the service sends the FCM
 * receipts itself today.
 */
class CyberTransferCompleted
{
    use Dispatchable;

    public function __construct(
        public readonly CyberTransfer $transfer,
        public readonly string $senderBalanceAfter,
    ) {}
}
