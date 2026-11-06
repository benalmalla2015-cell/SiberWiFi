<?php

namespace App\Http\Middleware;

use App\Services\AccContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Tenant gate for the whole accounting route group (PLAN §4).
 *
 * Runs after auth:sanctum. Accepts either a network owner (their own
 * tenant) or an active acc_agents enrollee (the owner's tenant) —
 * this is what lets the three roles log into the same app without
 * new auth tables. Anything else is a clean 403.
 */
class EnsureAccountingContext
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json([
                'success' => false,
                'message' => 'غير مصرح. يرجى تسجيل الدخول.',
            ], 401);
        }

        $ctx = AccContext::forUser($user);
        if ($ctx === null) {
            return response()->json([
                'success' => false,
                'code' => 'no_accounting_account',
                'message' => 'لا يوجد حساب محاسبة مرتبط بهذا المستخدم',
            ], 403);
        }

        $request->attributes->set(AccContext::REQUEST_KEY, $ctx);

        return $next($request);
    }
}
