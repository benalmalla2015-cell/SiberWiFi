<?php

namespace App\Listeners;

use App\Events\CyberTopupCompleted;
use App\Services\CyberAgentService;
use Illuminate\Support\Facades\Log;

/**
 * CYB-07 — accrues the agent's commission the moment a top-up
 * commits. Registered from routes/cyber/agent.php (the CYB-07-owned
 * fragment) so no shared provider file is touched; the service's
 * reconcile() covers any path where the event never fired.
 */
class CreditCyberAgentCommission
{
    public function __construct(private readonly CyberAgentService $agents) {}

    public function handle(CyberTopupCompleted $event): void
    {
        try {
            $this->agents->creditForTopup($event->topup);
        } catch (\Throwable $e) {
            // A commission write must never fail the top-up itself —
            // reconcile() picks the row up on the next earnings read.
            Log::warning('CyberNet agent commission failed: '.$e->getMessage());
        }
    }
}
