<?php

namespace App\Http\Middleware;

use App\Services\AccContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Route-level `acc:{permission}` check (PLAN §4). Applied as
 * `->middleware(AuthorizeAccPermission::class . ':agents.manage')`
 * inside api_accounting.php, on top of EnsureAccountingContext.
 */
class AuthorizeAccPermission
{
    public function handle(Request $request, Closure $next, string $permission): Response
    {
        $ctx = AccContext::fromRequest($request);

        if ($ctx === null || ! $ctx->can($permission)) {
            return response()->json([
                'success' => false,
                'code' => 'acc_forbidden',
                'message' => 'ليس لديك صلاحية لهذا القسم',
            ], 403);
        }

        return $next($request);
    }
}
