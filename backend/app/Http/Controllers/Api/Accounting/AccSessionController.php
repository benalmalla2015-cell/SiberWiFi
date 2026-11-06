<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\ExchangeRateSetting;
use App\Services\AccContext;
use App\Services\CurrencyService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Session bootstrap for the accounting section — the app calls this
 * right after login to learn which of the three roles the account
 * operates as and which surface to render (PLAN §1).
 */
class AccSessionController extends Controller
{
    public function me(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $agent = $ctx->agent;
        $user = $ctx->user;

        return response()->json([
            'success' => true,
            'data' => [
                'role' => $ctx->role,
                'owner_id' => $ctx->ownerId,
                'permissions' => $ctx->permissions(),
                'user' => [
                    'id' => $user->id,
                    'name' => $user->name,
                    'phone' => $user->phone,
                ],
                'agent' => $agent === null ? null : [
                    'id' => $agent->id,
                    'role' => $agent->role,
                    'display_name' => $agent->display_name,
                    'phone' => $agent->phone,
                    'cash_allowed' => $agent->cash_allowed,
                    'credit_allowed' => $agent->credit_allowed,
                    'status' => $agent->status,
                ],
            ],
        ]);
    }

    /**
     * The currencies money documents accept (ACC-05, PLAN §2.5) —
     * read-only over exchange_rate_settings; the app never edits
     * the rate, it just shows what to convert with.
     */
    public function currencies(): JsonResponse
    {
        $setting = ExchangeRateSetting::current();

        return response()->json([
            'success' => true,
            'data' => [
                'currencies' => [
                    ['code' => 'north', 'label' => CurrencyService::currencyLabel('north')],
                    ['code' => 'south', 'label' => CurrencyService::currencyLabel('south')],
                ],
                // How many south units equal 1 north unit.
                'north_to_south' => CurrencyService::multiplierNorthToSouth(),
                'base_currency' => $setting?->base_currency ?? 'north',
                'rate_percent' => $setting !== null ? (float) $setting->rate_percent : 100.0,
            ],
        ]);
    }
}
