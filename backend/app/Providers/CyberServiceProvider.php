<?php

namespace App\Providers;

use Illuminate\Support\Facades\Route;
use Illuminate\Support\ServiceProvider;

/**
 * CyberNet module bootstrap — Track CYB (Task CYB-00).
 *
 * Loads the isolated CyberNet route file under the /api prefix.
 * The route file itself only auto-loads fragments from routes/cyber/*.php
 * so each CYB task registers its endpoints in its own file without ever
 * touching shared route files (isolation contract, cyber_plan/PLAN.md §6).
 */
class CyberServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->mergeConfigFrom(config_path('cyber.php'), 'cyber');
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Route::middleware('api')
            ->prefix('api')
            ->group(base_path('routes/api_cyber.php'));
    }
}
