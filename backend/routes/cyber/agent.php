<?php

use App\Events\CyberTopupCompleted;
use App\Http\Controllers\Api\Cyber\CyberAgentController;
use App\Listeners\CreditCyberAgentCommission;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CyberNet agent routes — CYB-07 fragment
|--------------------------------------------------------------------------
| Loaded by routes/api_cyber.php under /api/cyber (name prefix cyber.).
|
| All endpoints are behind auth:sanctum — the authenticated user is
| the agent, same trust level as POST /cyber/topup (CYB-04).
|
| The commission listener is registered here (not in a shared
| provider) so the event wiring lives inside this task's scope;
| CyberAgentService::reconcile() backfills on read, so the ledger is
| complete even if this file is skipped under route:cache.
*/

Event::listen(CyberTopupCompleted::class, CreditCyberAgentCommission::class);

Route::middleware('auth:sanctum')->prefix('agent')->name('agent.')->group(function (): void {
    Route::get('profile', [CyberAgentController::class, 'profile'])->name('profile');
    Route::get('earnings', [CyberAgentController::class, 'earnings'])->name('earnings');
    Route::get('topups', [CyberAgentController::class, 'topups'])->name('topups');
});
