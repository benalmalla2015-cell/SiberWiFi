<?php

use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Accounting API routes — Track ACC (isolated file, frozen boundary)
|--------------------------------------------------------------------------
| Base: /api/network-owner/accounting/*
| Middleware mirrors the network-owner group in routes/api.php.
| Endpoints are appended here per sprint (ACC-01 … ACC-13) —
| routes/api.php must never be touched for accounting.
|
| Sprint ACC-00: intentionally empty.
*/

Route::middleware(['auth:sanctum', 'active', 'can:network_owner'])
    ->prefix('network-owner/accounting')
    ->group(function () {
        // ACC-01+: endpoints registered here.
    });
