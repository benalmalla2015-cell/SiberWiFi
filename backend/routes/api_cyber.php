<?php

use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CyberNet API routes — Track CYB (isolated file, frozen boundary)
|--------------------------------------------------------------------------
| Base: /api/cyber/*
|
| This file NEVER registers endpoints directly. It auto-loads every
| fragment in routes/cyber/*.php so parallel CYB tasks each own a file
| (e.g. routes/cyber/register.php, routes/cyber/billing.php) and never
| collide on a shared routes file.
|
| routes/api.php and routes/api_accounting.php must never be touched.
|
| Default middleware: sanctum auth. Public endpoints (e.g. registration)
| opt out inside their own fragment via ->withoutMiddleware() or by
| defining them before the auth group in their fragment file.
*/

// CYB-14: signature gate applies to every /cyber/* route when
// CYBER_HMAC_ENABLED=true — one switch, no per-fragment wiring.
$cyberMiddleware = config('cyber.hmac.enabled') ? ['cyber.hmac'] : [];

Route::prefix('cyber')->name('cyber.')->middleware($cyberMiddleware)->group(function (): void {
    foreach (glob(__DIR__.'/cyber/*.php') ?: [] as $fragment) {
        require $fragment;
    }
});
