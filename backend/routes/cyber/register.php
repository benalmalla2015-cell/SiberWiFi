<?php

use App\Http\Controllers\Api\Cyber\CyberRegisterController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CYB-03 — Registration & SIM number (loaded by routes/api_cyber.php)
|--------------------------------------------------------------------------
| POST /api/cyber/register          public, throttled (first-time enrolment)
| GET  /api/cyber/subscribers/{n}   sanctum (agent lookup, used by CYB-07)
| Feature gate (PLAN §6.3 rule 3): config('cyber.enabled').
*/

if (config('cyber.enabled', true)) {
    Route::post('register', [CyberRegisterController::class, 'register'])
        ->middleware('throttle:10,1')
        ->name('register');

    Route::get('subscribers/{sim_no}', [CyberRegisterController::class, 'show'])
        ->where('sim_no', '74[0-9]{7}')
        ->middleware(['auth:sanctum', 'throttle:60,1'])
        ->name('subscribers.show');
}
