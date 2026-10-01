<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureAccountActive
{
    /**
     * Reject requests from suspended accounts across the mobile API.
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user && ! $user->is_active) {
            return response()->json([
                'success' => false,
                'code'    => 'account_suspended',
                'message' => 'تم إيقاف الحساب من قبل إدارة التطبيق يرجى مراجعة الدعم الفني',
            ], 403);
        }

        return $next($request);
    }
}
