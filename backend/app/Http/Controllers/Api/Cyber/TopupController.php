<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Services\CyberBillingException;
use App\Services\CyberBillingService;
use Illuminate\Http\Request;

/**
 * POST /api/cyber/topup (CYB-04) — agent credits a subscriber by SIM
 * number; instant balance + FCM notification to the subscriber.
 */
class TopupController extends Controller
{
    public function store(Request $request, CyberBillingService $billing)
    {
        $prefix = preg_quote((string) config('cyber.sim_prefix', '74'), '/');

        $data = $request->validate([
            'sim_no' => ['required', 'string', 'regex:/^'.$prefix.'\d{7}$/'],
            'amount' => ['required', 'numeric', 'min:1', 'max:1000000'],
            'idempotency_key' => ['required', 'string', 'max:120'],
        ]);

        try {
            $result = $billing->topup(
                (int) $request->user()->id,
                $data['sim_no'],
                (float) $data['amount'],
                $data['idempotency_key']
            );
        } catch (CyberBillingException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], $e->status);
        }

        $topup = $result['topup'];

        return response()->json([
            'success' => true,
            'data' => [
                'topup_id' => $topup->id,
                'sim_no' => $topup->sim_no,
                'amount' => (float) $topup->amount,
                'currency' => $topup->currency,
                'balance' => (float) $result['balance'],
                'duplicate' => $result['duplicate'],
                'created_at' => $topup->created_at?->toIso8601String(),
            ],
        ]);
    }
}
