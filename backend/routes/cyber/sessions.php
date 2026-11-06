<?php

use App\Http\Controllers\Api\Cyber\SessionController;
use App\Http\Controllers\Api\Cyber\UsageController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CyberNet session log & usage — CYB-09 fragment
|--------------------------------------------------------------------------
| Loaded by routes/api_cyber.php under /api/cyber (name prefix cyber.).
|
| GET /api/cyber/sessions     — session log per SIM/device (live + closed)
| GET /api/cyber/usage/daily  — per-day consumption, 7/30-day chart window
|
| Both are subscriber device-bound: sim_no + device_id resolve against
| cyber_identities (CYB-04 convention — the enrolled device is the
| credential; subscribers own no users-account).
*/

if (config('cyber.enabled', true)) {
    Route::get('sessions', [SessionController::class, 'index'])->name('sessions.index');
    Route::get('usage/daily', [UsageController::class, 'daily'])->name('usage.daily');
}
