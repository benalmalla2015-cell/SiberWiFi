<?php

use App\Http\Controllers\Api\Accounting\AccAgentsController;
use App\Http\Controllers\Api\Accounting\AccBackupController;
use App\Http\Controllers\Api\Accounting\AccBalancesController;
use App\Http\Controllers\Api\Accounting\AccBillingController;
use App\Http\Controllers\Api\Accounting\AccCashBoxesController;
use App\Http\Controllers\Api\Accounting\AccCategoriesController;
use App\Http\Controllers\Api\Accounting\AccCollectionsController;
use App\Http\Controllers\Api\Accounting\AccDamagedController;
use App\Http\Controllers\Api\Accounting\AccDebtsController;
use App\Http\Controllers\Api\Accounting\AccDiscountTiersController;
use App\Http\Controllers\Api\Accounting\AccDistController;
use App\Http\Controllers\Api\Accounting\AccDocHeaderController;
use App\Http\Controllers\Api\Accounting\AccExpensesController;
use App\Http\Controllers\Api\Accounting\AccJournalController;
use App\Http\Controllers\Api\Accounting\AccPlatformSalesController;
use App\Http\Controllers\Api\Accounting\AccPosAppController;
use App\Http\Controllers\Api\Accounting\AccPosOrdersController;
use App\Http\Controllers\Api\Accounting\AccPosPointsController;
use App\Http\Controllers\Api\Accounting\AccPurchasesController;
use App\Http\Controllers\Api\Accounting\AccReportsController;
use App\Http\Controllers\Api\Accounting\AccReturnsController;
use App\Http\Controllers\Api\Accounting\AccSessionController;
use App\Http\Controllers\Api\Accounting\AccStockController;
use App\Http\Controllers\Api\Accounting\AccSuppliersController;
use App\Http\Controllers\Api\Accounting\AccSyncController;
use App\Http\Controllers\Api\Accounting\AccWebhooksController;
use App\Http\Controllers\Api\Accounting\AccWithdrawalsController;
use App\Http\Middleware\AuthorizeAccPermission;
use App\Http\Middleware\EnsureAccountingContext;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Accounting API routes — Track ACC (isolated file, frozen boundary)
|--------------------------------------------------------------------------
| Base: /api/network-owner/accounting/*
| Middleware mirrors the network-owner group in routes/api.php, except
| `can:network_owner` is replaced by EnsureAccountingContext — the
| acc_agents resolver that admits the three roles (owner/admin/
| distributor/pos) under the same login (PLAN §1, §4).
| Per-route `acc:{permission}` checks go through
| AuthorizeAccPermission. Numeric param constraints keep literal
| prefixes (pos/home, pos/orders …) free for later sprints.
|
| routes/api.php must never be touched for accounting.
*/

Route::middleware(['auth:sanctum', 'active', EnsureAccountingContext::class])
    ->prefix('network-owner/accounting')
    ->group(function () {

        // Session bootstrap — which role/surface this account gets.
        Route::get('/me', [AccSessionController::class, 'me']);

        $perm = fn (string $p) => AuthorizeAccPermission::class . ':' . $p;

        // ACC-03 — agents (المستخدمون): owner/admin only.
        Route::get('/agents', [AccAgentsController::class, 'index'])
            ->middleware($perm('agents.read'));
        Route::post('/agents', [AccAgentsController::class, 'store'])
            ->middleware($perm('agents.manage'));
        Route::put('/agents/{agent}', [AccAgentsController::class, 'update'])
            ->whereNumber('agent')
            ->middleware($perm('agents.manage'));
        Route::delete('/agents/{agent}', [AccAgentsController::class, 'destroy'])
            ->whereNumber('agent')
            ->middleware($perm('agents.manage'));

        // ACC-03 — POS points (نقاط البيع) + bound devices.
        Route::get('/pos', [AccPosPointsController::class, 'index'])
            ->middleware($perm('pos.read'));
        Route::post('/pos', [AccPosPointsController::class, 'store'])
            ->middleware($perm('pos.manage'));
        Route::put('/pos/{pos}', [AccPosPointsController::class, 'update'])
            ->whereNumber('pos')
            ->middleware($perm('pos.manage'));
        Route::delete('/pos/{pos}', [AccPosPointsController::class, 'destroy'])
            ->whereNumber('pos')
            ->middleware($perm('pos.manage'));

        Route::get('/pos/{pos}/devices', [AccPosPointsController::class, 'devices'])
            ->whereNumber('pos')
            ->middleware($perm('pos.read'));
        Route::post('/pos/{pos}/devices', [AccPosPointsController::class, 'storeDevice'])
            ->whereNumber('pos')
            ->middleware($perm('pos.manage'));
        Route::delete('/pos/{pos}/devices/{device}',
            [AccPosPointsController::class, 'destroyDevice'])
            ->whereNumber('pos')->whereNumber('device')
            ->middleware($perm('pos.manage'));

        // ACC-04 — POS bundle orders (طلبات نقاط البيع): management
        // surface for owner/admin + distributors (pos-orders.*).
        Route::get('/pos-orders', [AccPosOrdersController::class, 'index'])
            ->middleware($perm('pos-orders.read'));
        Route::post('/pos-orders', [AccPosOrdersController::class, 'store'])
            ->middleware($perm('pos-orders.decide'));
        Route::post('/pos-orders/{order}/approve', [AccPosOrdersController::class, 'approve'])
            ->whereNumber('order')
            ->middleware($perm('pos-orders.decide'));
        Route::post('/pos-orders/{order}/reject', [AccPosOrdersController::class, 'reject'])
            ->whereNumber('order')
            ->middleware($perm('pos-orders.decide'));

        // ACC-04 — distributor aliases (same pos-orders.* grants).
        Route::get('/dist/pos-orders', [AccPosOrdersController::class, 'index'])
            ->middleware($perm('pos-orders.read'));
        Route::post('/dist/pos-orders/{order}/approve', [AccPosOrdersController::class, 'approve'])
            ->whereNumber('order')
            ->middleware($perm('pos-orders.decide'));
        Route::post('/dist/pos-orders/{order}/reject', [AccPosOrdersController::class, 'reject'])
            ->whereNumber('order')
            ->middleware($perm('pos-orders.decide'));

        // ACC-06 — distributor surface: home read model + direct
        // sales + own register + report + commissions (dist.*).
        Route::get('/dist/home', [AccDistController::class, 'home'])
            ->middleware($perm('dist.read'));
        Route::get('/dist/sales', [AccDistController::class, 'sales'])
            ->middleware($perm('dist.read'));
        Route::post('/dist/sale', [AccDistController::class, 'storeSale'])
            ->middleware($perm('dist.sale'));
        Route::get('/dist/report', [AccDistController::class, 'report'])
            ->middleware($perm('dist.read'));
        Route::get('/dist/commissions', [AccDistController::class, 'commissions'])
            ->middleware($perm('dist.read'));

        // ACC-04 — POS surface: the pos agent orders for its own
        // bound point only (posapp.* grant).
        Route::get('/pos/orders', [AccPosOrdersController::class, 'myOrders'])
            ->middleware($perm('posapp.orders'));
        Route::post('/pos/orders', [AccPosOrdersController::class, 'storeMyOrder'])
            ->middleware($perm('posapp.orders'));

        // ACC-02 — card categories catalog (فئات الكروت).
        Route::get('/categories', [AccCategoriesController::class, 'index'])
            ->middleware($perm('categories.read'));
        Route::post('/categories', [AccCategoriesController::class, 'store'])
            ->middleware($perm('categories.manage'));
        Route::put('/categories/{category}', [AccCategoriesController::class, 'update'])
            ->whereNumber('category')
            ->middleware($perm('categories.manage'));
        Route::delete('/categories/{category}', [AccCategoriesController::class, 'destroy'])
            ->whereNumber('category')
            ->middleware($perm('categories.manage'));

        // ACC-02 — stock: reads auto-sync router cards first.
        Route::get('/stock', [AccStockController::class, 'index'])
            ->middleware($perm('stock.read'));
        Route::get('/stock/movements', [AccStockController::class, 'movements'])
            ->middleware($perm('stock.read'));
        Route::post('/stock/adjust', [AccStockController::class, 'adjust'])
            ->middleware($perm('stock.manage'));
        Route::post('/stock/sync', [AccStockController::class, 'sync'])
            ->middleware($perm('stock.manage'));
        Route::post('/stock/import', [AccStockController::class, 'import'])
            ->middleware($perm('stock.manage'));
        Route::get('/stock/imports', [AccStockController::class, 'imports'])
            ->middleware($perm('stock.read'));

        // ACC-02 — suppliers + purchases.
        Route::get('/suppliers', [AccSuppliersController::class, 'index'])
            ->middleware($perm('suppliers.read'));
        Route::post('/suppliers', [AccSuppliersController::class, 'store'])
            ->middleware($perm('suppliers.manage'));
        Route::put('/suppliers/{supplier}', [AccSuppliersController::class, 'update'])
            ->whereNumber('supplier')
            ->middleware($perm('suppliers.manage'));
        Route::delete('/suppliers/{supplier}', [AccSuppliersController::class, 'destroy'])
            ->whereNumber('supplier')
            ->middleware($perm('suppliers.manage'));

        Route::get('/purchases', [AccPurchasesController::class, 'index'])
            ->middleware($perm('purchases.read'));
        Route::post('/purchases', [AccPurchasesController::class, 'store'])
            ->middleware($perm('purchases.manage'));

        // ACC-02 — returns + damaged registers.
        Route::get('/returns', [AccReturnsController::class, 'index'])
            ->middleware($perm('returns.read'));
        Route::post('/returns', [AccReturnsController::class, 'store'])
            ->middleware($perm('returns.manage'));
        Route::get('/damaged', [AccDamagedController::class, 'index'])
            ->middleware($perm('damaged.read'));
        Route::post('/damaged', [AccDamagedController::class, 'store'])
            ->middleware($perm('damaged.manage'));

        // ACC-05 — currencies, read-only over the platform's
        // exchange_rate_settings (PLAN §2.5).
        Route::get('/currencies', [AccSessionController::class, 'currencies']);

        // ACC-05 — collections (money in). Distributors reach the
        // same handlers through /dist aliases (collections.* grant).
        Route::get('/collections', [AccCollectionsController::class, 'index'])
            ->middleware($perm('collections.read'));
        Route::post('/collections', [AccCollectionsController::class, 'store'])
            ->middleware($perm('collections.manage'));
        Route::get('/dist/collections', [AccCollectionsController::class, 'index'])
            ->middleware($perm('collections.read'));
        Route::post('/dist/collections', [AccCollectionsController::class, 'store'])
            ->middleware($perm('collections.manage'));

        // ACC-05 — debts + atomic settlement (debts.* grant).
        Route::get('/debts', [AccDebtsController::class, 'index'])
            ->middleware($perm('debts.read'));
        Route::post('/debts', [AccDebtsController::class, 'store'])
            ->middleware($perm('debts.manage'));
        Route::get('/debts/{debt}/payments', [AccDebtsController::class, 'payments'])
            ->whereNumber('debt')
            ->middleware($perm('debts.read'));
        Route::post('/debts/{debt}/pay', [AccDebtsController::class, 'pay'])
            ->whereNumber('debt')
            ->middleware($perm('debts.manage'));
        Route::get('/dist/debts', [AccDebtsController::class, 'index'])
            ->middleware($perm('debts.read'));
        Route::post('/dist/debts/{debt}/pay', [AccDebtsController::class, 'pay'])
            ->whereNumber('debt')
            ->middleware($perm('debts.manage'));

        // ACC-05 — POS surface: collections recorded on own point.
        Route::get('/pos/collections-received', [AccCollectionsController::class, 'received'])
            ->middleware($perm('posapp.collections'));

        // ACC-05 — cash boxes + inter-box transfers (owner/admin).
        Route::get('/cash-boxes', [AccCashBoxesController::class, 'index'])
            ->middleware($perm('cashboxes.read'));
        Route::post('/cash-boxes', [AccCashBoxesController::class, 'store'])
            ->middleware($perm('cashboxes.manage'));
        Route::put('/cash-boxes/{box}', [AccCashBoxesController::class, 'update'])
            ->whereNumber('box')
            ->middleware($perm('cashboxes.manage'));
        Route::get('/cash-boxes/transfers', [AccCashBoxesController::class, 'transfers'])
            ->middleware($perm('cashboxes.read'));
        Route::post('/cash-boxes/transfer', [AccCashBoxesController::class, 'transfer'])
            ->middleware($perm('cashboxes.manage'));

        // ACC-05 — daily expenses + categories (owner/admin).
        Route::get('/expenses', [AccExpensesController::class, 'index'])
            ->middleware($perm('expenses.read'));
        Route::post('/expenses', [AccExpensesController::class, 'store'])
            ->middleware($perm('expenses.manage'));
        Route::delete('/expenses/{expense}', [AccExpensesController::class, 'destroy'])
            ->whereNumber('expense')
            ->middleware($perm('expenses.manage'));
        Route::get('/expense-categories', [AccExpensesController::class, 'categories'])
            ->middleware($perm('expenses.read'));
        Route::post('/expense-categories', [AccExpensesController::class, 'storeCategory'])
            ->middleware($perm('expenses.manage'));
        Route::put('/expense-categories/{category}', [AccExpensesController::class, 'updateCategory'])
            ->whereNumber('category')
            ->middleware($perm('expenses.manage'));
        Route::delete('/expense-categories/{category}', [AccExpensesController::class, 'destroyCategory'])
            ->whereNumber('category')
            ->middleware($perm('expenses.manage'));

        // ACC-07 — POS app surface: home aggregate, points/profit
        // ledger, own withdrawals, and instant card-for-points
        // exchange. All under the posapp.* grant (pos agents).
        Route::get('/pos/home', [AccPosAppController::class, 'home'])
            ->middleware($perm('posapp.home'));
        Route::get('/pos/ledger', [AccPosAppController::class, 'ledger'])
            ->middleware($perm('posapp.home'));
        Route::get('/pos/withdrawals', [AccPosAppController::class, 'withdrawals'])
            ->middleware($perm('posapp.withdrawals'));
        Route::post('/pos/withdrawals', [AccPosAppController::class, 'storeWithdrawal'])
            ->middleware($perm('posapp.withdrawals'));
        Route::post('/pos/withdrawals/{withdrawal}/cancel', [AccPosAppController::class, 'cancelWithdrawal'])
            ->whereNumber('withdrawal')
            ->middleware($perm('posapp.withdrawals'));
        Route::get('/pos/exchanges', [AccPosAppController::class, 'exchanges'])
            ->middleware($perm('posapp.exchange'));
        Route::post('/pos/exchange-cards', [AccPosAppController::class, 'exchange'])
            ->middleware($perm('posapp.exchange'));

        // ACC-07 — distributor alias: the same withdrawal request
        // surface for the distributor role (dist.* grant).
        Route::get('/dist/withdrawals', [AccPosAppController::class, 'withdrawals'])
            ->middleware($perm('dist.withdrawals'));
        Route::post('/dist/withdrawals', [AccPosAppController::class, 'storeWithdrawal'])
            ->middleware($perm('dist.withdrawals'));
        Route::post('/dist/withdrawals/{withdrawal}/cancel', [AccPosAppController::class, 'cancelWithdrawal'])
            ->whereNumber('withdrawal')
            ->middleware($perm('dist.withdrawals'));

        // ACC-07 — withdrawal review (owner/admin): the decide path
        // that pays out of a cash box or refunds the profit hold.
        Route::get('/withdrawals', [AccWithdrawalsController::class, 'index'])
            ->middleware($perm('withdrawals.read'));
        Route::post('/withdrawals/{withdrawal}/approve', [AccWithdrawalsController::class, 'approve'])
            ->whereNumber('withdrawal')
            ->middleware($perm('withdrawals.decide'));
        Route::post('/withdrawals/{withdrawal}/paid', [AccWithdrawalsController::class, 'paid'])
            ->whereNumber('withdrawal')
            ->middleware($perm('withdrawals.decide'));
        Route::post('/withdrawals/{withdrawal}/reject', [AccWithdrawalsController::class, 'reject'])
            ->whereNumber('withdrawal')
            ->middleware($perm('withdrawals.decide'));

        // ACC-08 — platform customer-app sales → card_purchase_platform
        // entries + stock out. Read-only on transactions/cards —
        // enforced by AccPlatformReadOnly inside the service.
        Route::get('/platform-sales', [AccPlatformSalesController::class, 'index'])
            ->middleware($perm('platform.read'));
        Route::post('/platform-sales/sync', [AccPlatformSalesController::class, 'sync'])
            ->middleware($perm('platform.manage'));
        Route::get('/posting-map', [AccPlatformSalesController::class, 'postingMap'])
            ->middleware($perm('platform.read'));
        Route::put('/posting-map', [AccPlatformSalesController::class, 'updatePostingMap'])
            ->middleware($perm('platform.manage'));

        // ACC-09 — reports + audit trail (owner/admin; read-only).
        Route::get('/summary', [AccReportsController::class, 'summary'])
            ->middleware($perm('reports.read'));
        Route::get('/dashboard/trend', [AccReportsController::class, 'trend'])
            ->middleware($perm('reports.read'));
        Route::get('/reports/sales', [AccReportsController::class, 'sales'])
            ->middleware($perm('reports.read'));
        Route::get('/reports/pos-performance', [AccReportsController::class, 'posPerformance'])
            ->middleware($perm('reports.read'));
        Route::get('/reports/distributor-commissions', [AccReportsController::class, 'commissions'])
            ->middleware($perm('reports.read'));
        Route::get('/reports/collections-daily', [AccReportsController::class, 'collectionsDaily'])
            ->middleware($perm('reports.read'));
        Route::get('/journal', [AccJournalController::class, 'index'])
            ->middleware($perm('journal.read'));
        Route::get('/journal/{entry}', [AccJournalController::class, 'show'])
            ->whereNumber('entry')
            ->middleware($perm('journal.read'));
        Route::get('/audit-log', [AccReportsController::class, 'auditLog'])
            ->middleware($perm('audit.read'));

        // ACC-11 — subscription & entitlement layer (PLAN §6): same
        // flow as /network-owner/mikrotik/* but tenant-keyed. The
        // entitlements probe stays open to every ctx role so
        // distributor/pos surfaces can resolve their gates; the paid
        // actions sit behind billing.* (owner/admin only).
        Route::get('/billing/entitlements', [AccBillingController::class, 'entitlements']);
        Route::get('/billing/plans', [AccBillingController::class, 'plans'])
            ->middleware($perm('billing.read'));
        Route::post('/billing/subscribe', [AccBillingController::class, 'subscribe'])
            ->middleware($perm('billing.manage'));
        Route::get('/billing/payments', [AccBillingController::class, 'paymentRequests'])
            ->middleware($perm('billing.read'));
        Route::post('/billing/payments', [AccBillingController::class, 'storePaymentRequest'])
            ->middleware($perm('billing.manage'));

        // ACC-12 — offline sync center. Pushing queued ops is open to
        // every role that can write offline (sync.push is granted to
        // owner/admin/distributor/pos); reading the queue and
        // resolving needs_review stays owner/admin (sync.*).
        Route::get('/sync/pending', [AccSyncController::class, 'pending'])
            ->middleware($perm('sync.read'));
        Route::get('/sync/queue', [AccSyncController::class, 'queue'])
            ->middleware($perm('sync.read'));
        Route::post('/sync/push', [AccSyncController::class, 'push'])
            ->middleware($perm('sync.push'));
        Route::post('/sync/{op}/retry', [AccSyncController::class, 'retry'])
            ->whereNumber('op')
            ->middleware($perm('sync.manage'));
        Route::post('/sync/{op}/discard', [AccSyncController::class, 'discard'])
            ->whereNumber('op')
            ->middleware($perm('sync.manage'));

        // ACC-12 — backup snapshots: export, list, download, import,
        // and atomic restore (owner/admin via backup.*).
        Route::post('/backup', [AccBackupController::class, 'store'])
            ->middleware($perm('backup.manage'));
        Route::get('/backups', [AccBackupController::class, 'index'])
            ->middleware($perm('backup.read'));
        Route::post('/backups/import', [AccBackupController::class, 'import'])
            ->middleware($perm('backup.manage'));
        Route::get('/backups/{backup}/download', [AccBackupController::class, 'download'])
            ->whereNumber('backup')
            ->middleware($perm('backup.read'));
        Route::post('/backups/{backup}/restore', [AccBackupController::class, 'restore'])
            ->whereNumber('backup')
            ->middleware($perm('backup.manage'));

        // ACC-12 — printed-document header settings (settings.*).
        Route::get('/doc-header', [AccDocHeaderController::class, 'show'])
            ->middleware($perm('settings.read'));
        Route::put('/doc-header', [AccDocHeaderController::class, 'update'])
            ->middleware($perm('settings.manage'));
        Route::post('/doc-header/logo', [AccDocHeaderController::class, 'uploadLogo'])
            ->middleware($perm('settings.manage'));
        Route::delete('/doc-header/logo', [AccDocHeaderController::class, 'removeLogo'])
            ->middleware($perm('settings.manage'));
        Route::get('/doc-header/logo', [AccDocHeaderController::class, 'logo'])
            ->middleware($perm('settings.read'));

        // ACC-10 — discount/reward tiers (شرائح الخصم): management
        // CRUD + a match preview of what a document would earn.
        Route::get('/discount-tiers', [AccDiscountTiersController::class, 'index'])
            ->middleware($perm('discount-tiers.read'));
        Route::post('/discount-tiers', [AccDiscountTiersController::class, 'store'])
            ->middleware($perm('discount-tiers.manage'));
        Route::post('/discount-tiers/match', [AccDiscountTiersController::class, 'match'])
            ->middleware($perm('discount-tiers.read'));
        Route::put('/discount-tiers/{tier}', [AccDiscountTiersController::class, 'update'])
            ->whereNumber('tier')
            ->middleware($perm('discount-tiers.manage'));
        Route::delete('/discount-tiers/{tier}', [AccDiscountTiersController::class, 'destroy'])
            ->whereNumber('tier')
            ->middleware($perm('discount-tiers.manage'));

        // ACC-10 — party balances read model (أرصدة الأطراف).
        Route::get('/balances', [AccBalancesController::class, 'index'])
            ->middleware($perm('balances.read'));

        // ACC-10 — WhatsApp event templates (قوالب إشعارات واتساب):
        // CRUD + render preview + the due-debt reminder list.
        Route::get('/webhook-events', [AccWebhooksController::class, 'index'])
            ->middleware($perm('webhooks.read'));
        Route::post('/webhook-events', [AccWebhooksController::class, 'store'])
            ->middleware($perm('webhooks.manage'));
        Route::put('/webhook-events/{event}', [AccWebhooksController::class, 'update'])
            ->whereNumber('event')
            ->middleware($perm('webhooks.manage'));
        Route::delete('/webhook-events/{event}', [AccWebhooksController::class, 'destroy'])
            ->whereNumber('event')
            ->middleware($perm('webhooks.manage'));
        Route::post('/webhook-events/{event}/preview', [AccWebhooksController::class, 'preview'])
            ->whereNumber('event')
            ->middleware($perm('webhooks.read'));
        Route::get('/notifications/debt-due', [AccWebhooksController::class, 'dueDebts'])
            ->middleware($perm('webhooks.read'));
    });
