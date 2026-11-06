<?php

use App\Http\Controllers\Api\Cyber\CreditController;
use App\Http\Controllers\Api\Cyber\TransferController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CYB-06 — balance transfer + «سلفني» (loaded by routes/api_cyber.php)
|--------------------------------------------------------------------------
| POST /api/cyber/transfer — subscriber→subscriber balance transfer by
|   SIM number; sender is bound by sim_no + device_id like the CYB-04
|   subscriber endpoints.
| POST /api/cyber/borrow   — «سلفني» borrowed balance, collected from
|   the next incoming top-up/transfer automatically.
| GET  /api/cyber/credit   — live credit limit / outstanding position.
| Feature gate (PLAN §6.3 rule 3): config('cyber.enabled').
*/

if (config('cyber.enabled', true)) {
    Route::post('transfer', [TransferController::class, 'store'])->name('transfer');
    Route::post('borrow', [CreditController::class, 'store'])->name('borrow');
    Route::get('credit', [CreditController::class, 'show'])->name('credit.show');
}
