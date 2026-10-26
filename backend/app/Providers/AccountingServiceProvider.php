<?php

namespace App\Providers;

use Illuminate\Support\Facades\Route;
use Illuminate\Support\ServiceProvider;

/**
 * Accounting module bootstrap — Track ACC (Sprint ACC-00).
 *
 * Loads the isolated accounting route file under the /api prefix.
 * The route file is intentionally empty until ACC-01+; a dedicated
 * provider keeps every future accounting change out of the shared
 * bootstrap files (isolation contract, PLAN.md §0).
 */
class AccountingServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Route::middleware('api')
            ->prefix('api')
            ->group(base_path('routes/api_accounting.php'));
    }
}
