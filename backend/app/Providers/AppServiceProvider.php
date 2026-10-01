<?php

namespace App\Providers;

use App\Helpers\PermissionHelper;
use App\Models\PayoutRequest;
use App\Observers\PayoutRequestObserver;
use Illuminate\Auth\Access\Response;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
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
        PayoutRequest::observe(PayoutRequestObserver::class);

        Gate::define('network_owner', function ($user) {
            return $user->type === 'network_owner' || $user->networks()->exists() || $user->networkOwnerProfile()->exists();
        });

        Gate::before(function ($user, string $ability, $model = null): ?Response {
            if ($user === null) {
                return null;
            }

            // Super-admin bypass.
            if ($user->hasAnyPermission(['all']) || $user->hasRole('super-admin')) {
                return Response::allow();
            }

            $slug   = PermissionHelper::resourceSlugForModel($model);
            $action = PermissionHelper::actionForAbility($ability);

            if ($slug !== null && $action !== null) {
                if ($user->hasAnyPermission([
                    "{$action}_{$slug}",
                    "{$action}_all",
                    'all',
                ])) {
                    return Response::allow();
                }

                return Response::deny('ليس لديك الصلاحية اللازمة.');
            }

            if ($action !== null) {
                if ($user->hasAnyPermission(["{$action}_all", 'all'])) {
                    return Response::allow();
                }
            }

            return null;
        });
    }
}
