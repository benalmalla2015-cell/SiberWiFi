<?php

use App\Http\Controllers\Api\Cyber\PackageController;
use App\Http\Controllers\Api\Cyber\RadiusController;
use App\Http\Controllers\Api\Cyber\SubscriptionController;
use App\Http\Controllers\Api\Cyber\TopupController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CyberNet billing routes — CYB-04 fragment
|--------------------------------------------------------------------------
| Loaded by routes/api_cyber.php under /api/cyber (name prefix cyber.).
|
| Three trust levels:
| - agent app (sanctum user)          → POST /topup
| - subscriber device (sim+device_id) → packages list + subscriptions
| - RADIUS engine (bearer token)      → /radius/events + /radius/authorize
*/

// Agent app — authenticated user.
Route::middleware('auth:sanctum')->group(function (): void {
    Route::post('topup', [TopupController::class, 'store'])->name('topup');
});

// Subscriber device — bound by cyber_identities.device_id, no user account.
Route::get('packages', [PackageController::class, 'index'])->name('packages');
Route::post('subscriptions', [SubscriptionController::class, 'store'])->name('subscriptions.store');
Route::get('subscriptions/current', [SubscriptionController::class, 'current'])->name('subscriptions.current');

// Engine (cyber-radius on the VPS) — bearer CYBER_ENGINE_TOKEN.
Route::post('radius/events', [RadiusController::class, 'events'])->name('radius.events');
Route::post('radius/authorize', [RadiusController::class, 'authorize'])->name('radius.authorize');
