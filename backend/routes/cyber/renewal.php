<?php

use App\Http\Controllers\Api\Cyber\AutoRenewController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CyberNet auto-renew routes — CYB-08 fragment
|--------------------------------------------------------------------------
| Loaded by routes/api_cyber.php under /api/cyber (name prefix cyber.).
|
| PATCH /api/cyber/subscriptions/{subscription}/auto-renew — toggles
| the flag from the client app; device-bound (sim_no + device_id) like
| the other subscriber endpoints in billing.php.
*/

Route::patch('subscriptions/{subscription}/auto-renew', [AutoRenewController::class, 'update'])
    ->name('subscriptions.auto_renew');
