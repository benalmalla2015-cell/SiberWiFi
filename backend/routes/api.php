<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ChatController;
use App\Http\Controllers\Api\ChargingPointController;
use App\Http\Controllers\Api\HomeController;
use App\Http\Controllers\Api\MaintenanceModeController;
use App\Http\Controllers\Api\NetworkController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\PayoutController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\RegionController;
use App\Http\Controllers\Api\SupportTicketController;
use App\Http\Controllers\Api\TopupController;
use App\Http\Controllers\Api\TransactionController;
use App\Http\Controllers\Api\WalletController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerDashboardController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerNetworkController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerCardController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerStatsController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerRatingController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerReportController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerChargingPointController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerNotificationController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerPayoutController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerMikrotikController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerMikrotikSubscriptionController;
use App\Http\Controllers\Api\NetworkOwner\NetworkOwnerMikrotikPageController;
use Illuminate\Support\Facades\Route;

// ─── Public routes ────────────────────────────────────────────────
Route::post('/auth/register',              [AuthController::class, 'register']);
Route::post('/auth/register-network-owner', [AuthController::class, 'registerNetworkOwner']);
Route::post('/auth/login',                   [AuthController::class, 'login']);

// Public lookups
Route::get('/maintenance-mode/{app}',               [MaintenanceModeController::class, 'status'])->middleware('throttle:60,1');

Route::get('/regions',                              [RegionController::class, 'index']);
Route::get('/regions/{id}/directorates',            [RegionController::class, 'directorates']);
Route::get('/governorates',                          [RegionController::class, 'allGovernorates']);
Route::get('/sub-directorates',                       [RegionController::class, 'allSubDirectorates']);
Route::get('/directorates/{id}/sub-directorates',   [RegionController::class, 'subDirectorates']);
Route::get('/exchange-rate',                        [RegionController::class, 'exchangeRate']);
Route::get('/charging-points',                      [ChargingPointController::class, 'index']);

// Rendered hotspot login pages — PUBLIC: the router itself downloads
// these via /tool/fetch (no auth header possible). Folders expire 24h.
Route::get('/mikrotik-pages/{render}/{file}',
    [NetworkOwnerMikrotikPageController::class, 'serve'])
    ->middleware('throttle:120,1');

// ─── Authenticated routes ──────────────────────────────────────────
// Logout stays reachable for suspended accounts so the app can clean up
// its session after receiving the 403 account_suspended response.
Route::middleware('auth:sanctum')->post('/auth/logout', [AuthController::class, 'logout']);

// Account deletion is also reachable for suspended accounts.
Route::middleware('auth:sanctum')->post('/auth/account/delete', [AuthController::class, 'deleteAccount']);

Route::middleware(['auth:sanctum', 'active'])->group(function () {

    // Auth
    Route::get('/auth/me',               [AuthController::class, 'me']);
    Route::post('/auth/fcm-token',       [AuthController::class, 'updateFcmToken']);
    Route::get('/auth/payout-details',   [AuthController::class, 'payoutDetails']);
    Route::put('/auth/payout-details',   [AuthController::class, 'updatePayoutDetails']);

    // Pending network owner can view/update their own network
    Route::get('/auth/my-network',       [AuthController::class, 'myNetwork']);
    Route::post('/auth/my-network',      [AuthController::class, 'updateMyNetwork']);

    // Home (slider, top networks, offers)
    Route::get('/home', [HomeController::class, 'index']);
    Route::get('/daily-offers', [HomeController::class, 'dailyOffers']);

    // Networks
    Route::get('/networks',                       [NetworkController::class, 'index']);
    Route::get('/networks/{id}',                  [NetworkController::class, 'show']);
    Route::get('/networks/{id}/categories',       [NetworkController::class, 'categories']);
    Route::post('/networks/{id}/rate',            [NetworkController::class, 'rate']);
    Route::post('/networks/{id}/report',          [NetworkController::class, 'report']);
    Route::post('/networks/{id}/favorite',        [NetworkController::class, 'toggleFavorite']);
    Route::post('/networks/{id}/pin',             [NetworkController::class, 'togglePin']);
    Route::get('/favorites',                       [NetworkController::class, 'favorites']);

    // Transactions (card purchases)
    Route::post('/transactions/purchase',         [TransactionController::class, 'purchase']);
    Route::post('/transactions/purchase-advance', [TransactionController::class, 'purchaseAdvance']);
    Route::get('/transactions',                   [TransactionController::class, 'history']);
    Route::get('/transactions/{id}',              [TransactionController::class, 'show']);

    // Bank accounts (shown in customer app top-up screen)
    Route::get('/bank-accounts',                  [WalletController::class, 'bankAccounts']);

    // Instant top-up (TaizTel provider) — wallet-billed services
    Route::get('/topup/services',                 [TopupController::class, 'services']);
    Route::post('/topup/query',                   [TopupController::class, 'query'])->middleware('throttle:30,1');
    Route::get('/topup/offers',                   [TopupController::class, 'offers'])->middleware('throttle:30,1');
    Route::get('/topup/quote',                    [TopupController::class, 'quote'])->middleware('throttle:60,1');
    Route::post('/topup/pay',                     [TopupController::class, 'pay'])->middleware('throttle:15,1');
    Route::post('/topup/game',                    [TopupController::class, 'game'])->middleware('throttle:15,1');
    Route::post('/topup/offer/activate',          [TopupController::class, 'activateOffer'])->middleware('throttle:15,1');
    Route::get('/topup/orders',                   [TopupController::class, 'orders']);
    Route::get('/topup/orders/{id}/status',       [TopupController::class, 'orderStatus'])->middleware('throttle:30,1');

    // Wallet
    Route::get('/wallet/balance',                 [WalletController::class, 'balance']);
    Route::get('/wallet/logs',                    [WalletController::class, 'logs']);
    Route::get('/wallet/customers/search',        [WalletController::class, 'searchCustomer'])->middleware('throttle:30,1');
    Route::post('/wallet/topup',                  [WalletController::class, 'topup']);
    Route::post('/wallet/transfer',               [WalletController::class, 'transfer'])->middleware('throttle:20,1');

    // Charging points for customer
    Route::get('/charging-points/me',             [ChargingPointController::class, 'me']);

    // Payout requests (network owners only)
    Route::get('/payouts',                        [PayoutController::class, 'index']);
    Route::post('/payouts',                       [PayoutController::class, 'store']);
    Route::post('/payouts/{id}/confirm',          [PayoutController::class, 'confirmReceipt']);

    // Notifications
    Route::get('/notifications',                  [NotificationController::class, 'index']);
    Route::post('/notifications/{id}/read',       [NotificationController::class, 'markRead']);
    Route::post('/notifications/read-all',        [NotificationController::class, 'markAllRead']);

    // Support
    Route::get('/support-tickets',                [SupportTicketController::class, 'index']);
    Route::post('/support-tickets',               [SupportTicketController::class, 'store']);

    // Profile
    Route::put('/profile',                        [ProfileController::class, 'update']);
    Route::post('/profile/avatar',                [ProfileController::class, 'updateAvatar']);
    Route::put('/profile/password',               [ProfileController::class, 'changePassword']);
    Route::get('/profile/referral',               [ProfileController::class, 'referralInfo']);

    // Chat
    Route::get('/chat/{networkId}',               [ChatController::class, 'messages']);
    Route::post('/chat/{networkId}',              [ChatController::class, 'send']);
    Route::post('/chat/{networkId}/read',         [ChatController::class, 'markRead']);

    // ─── Network Owner routes ──────────────────────────────────────
    Route::prefix('network-owner')->middleware('can:network_owner')->group(function () {
        Route::get('/dashboard',                  [NetworkOwnerDashboardController::class, 'index']);
        Route::get('/transactions',               [NetworkOwnerDashboardController::class, 'transactions']);
        Route::get('/networks',                   [NetworkOwnerNetworkController::class, 'index']);
        Route::post('/networks',                  [NetworkOwnerNetworkController::class, 'store']);
        Route::put('/networks/{id}',              [NetworkOwnerNetworkController::class, 'update']);
        Route::get('/cards',                      [NetworkOwnerCardController::class, 'index']);
        Route::post('/cards/upload',              [NetworkOwnerCardController::class, 'upload']);
        Route::get('/cards/categories',           [NetworkOwnerCardController::class, 'categories']);
        Route::post('/cards/categories',          [NetworkOwnerCardController::class, 'storeCategory']);
        Route::put('/cards/categories/{id}',      [NetworkOwnerCardController::class, 'updateCategory']);
        Route::put('/cards/categories/{id}/advance-settings', [NetworkOwnerCardController::class, 'updateAdvanceSettings']);

        Route::get('/conversations',              [ChatController::class, 'conversations']);

        // Stats (charts)
        Route::get('/stats',                      [NetworkOwnerStatsController::class, 'index']);

        // Ratings
        Route::get('/ratings',                    [NetworkOwnerRatingController::class, 'index']);
        Route::post('/ratings/{id}/reply',         [NetworkOwnerRatingController::class, 'reply']);

        // Reports
        Route::get('/reports',                    [NetworkOwnerReportController::class, 'index']);
        Route::post('/reports/{id}/reply',        [NetworkOwnerReportController::class, 'reply']);

        // Charging points managed by network owner
        Route::get('/charging-points',            [NetworkOwnerChargingPointController::class, 'index']);
        Route::post('/charging-points',           [NetworkOwnerChargingPointController::class, 'store']);
        Route::put('/charging-points/{id}',       [NetworkOwnerChargingPointController::class, 'update']);
        Route::delete('/charging-points/{id}',    [NetworkOwnerChargingPointController::class, 'destroy']);

        // Notifications
        Route::get('/notifications',              [NetworkOwnerNotificationController::class, 'index']);
        Route::post('/notifications/{id}/read',   [NetworkOwnerNotificationController::class, 'markRead']);
        Route::post('/notifications/read-all',    [NetworkOwnerNotificationController::class, 'markAllRead']);

        // Payout requests
        Route::get('/payouts',                    [NetworkOwnerPayoutController::class, 'index']);
        Route::post('/payouts',                   [NetworkOwnerPayoutController::class, 'store']);
        Route::post('/payouts/{id}/confirm-receipt', [NetworkOwnerPayoutController::class, 'confirmReceipt']);

        // MikroTik router registry — the app upserts here after each
        // successful RouterOS connection; router passwords never leave
        // the device (api_password field stays optional/unused).
        Route::get('/mikrotik/routers',           [NetworkOwnerMikrotikController::class, 'index']);
        Route::post('/mikrotik/routers/sync',     [NetworkOwnerMikrotikController::class, 'sync']);
        Route::delete('/mikrotik/routers/{id}',   [NetworkOwnerMikrotikController::class, 'destroy']);

        // MikroTik subscription & entitlement layer
        Route::get('/mikrotik/entitlements',      [NetworkOwnerMikrotikSubscriptionController::class, 'entitlements']);
        Route::get('/mikrotik/plans',             [NetworkOwnerMikrotikSubscriptionController::class, 'plans']);
        Route::post('/mikrotik/subscribe',        [NetworkOwnerMikrotikSubscriptionController::class, 'subscribe']);
        Route::get('/mikrotik/payments',          [NetworkOwnerMikrotikSubscriptionController::class, 'paymentRequests']);
        Route::post('/mikrotik/payments',         [NetworkOwnerMikrotikSubscriptionController::class, 'storePaymentRequest']);

        // Hotspot login-page template store (Sprint: pages gallery)
        Route::get('/mikrotik/page-templates',    [NetworkOwnerMikrotikPageController::class, 'index']);
        Route::post('/mikrotik/page-templates/render', [NetworkOwnerMikrotikPageController::class, 'render']);
    });
});
