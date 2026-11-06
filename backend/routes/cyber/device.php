<?php

use App\Http\Controllers\Api\Cyber\DeviceController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CYB-05 — Client app device routes (loaded by routes/api_cyber.php)
|--------------------------------------------------------------------------
| The client app has no users-account; the enrolled device (sim_no +
| device_id against cyber_identities) is the credential, same binding
| rule as CYB-04 subscription endpoints.
|
| POST /api/cyber/identity/bind   attach device_id + fcm_token (FCM
|                               pushes of CYB-04 top-ups reach the device)
| GET  /api/cyber/activity        transaction log: top-ups, subscriptions,
|                                 RADIUS usage sessions
|
| Contract (fcm_token): field exists on cyber_identities (migration
| 000007, CYB-04). Nullable — bind succeeds without it where Firebase is
| unavailable; CyberBillingService::notifyTopup only pushes to rows that
| carry a token.
|
| Feature gate (PLAN §6.3 rule 3): config('cyber.enabled').
*/

if (config('cyber.enabled', true)) {
    Route::post('identity/bind', [DeviceController::class, 'bind'])
        ->middleware('throttle:60,1')
        ->name('identity.bind');

    Route::get('identity/certificate', [DeviceController::class, 'certificate'])
        ->middleware('throttle:60,1')
        ->name('identity.certificate');

    Route::get('activity', [DeviceController::class, 'activity'])
        ->middleware('throttle:60,1')
        ->name('activity');

    // CYB-13 — Google Play account-deletion requirement.
    Route::delete('account', [DeviceController::class, 'destroy'])
        ->middleware('throttle:10,1')
        ->name('account.destroy');
}
