<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Services\CyberBillingException;
use App\Services\CyberBillingService;
use App\Services\CyberCreditService;
use Illuminate\Http\Request;

/**
 * «سلفني» subscriber credit endpoints (CYB-06), device-bound like the
 * rest of the subscriber surface:
 *
 * POST /api/cyber/borrow — add borrowed balance within the credit
 *   limit; rejected while a previous debt is still outstanding.
 * GET  /api/cyber/credit — the live limit/outstanding position.
 */
class CreditController extends Controller
{
    public function store(Request $request, CyberBillingService $billing, CyberCreditService $credit)
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'max:16'],
            'device_id' => ['required', 'string', 'max:120'],
            'amount' => ['required', 'numeric', 'min:1', 'max:1000000'],
            'idempotency_key' => ['nullable', 'string', 'max:120'],
        ]);

        $subscriber = $billing->subscriberByDevice($data['sim_no'], $data['device_id']);
        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        try {
            $result = $credit->borrow($subscriber, (float) $data['amount'], $data['idempotency_key'] ?? null);
        } catch (CyberBillingException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], $e->status);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'event_id' => $result['event']->id,
                'borrowed' => (float) $result['event']->amount,
                'balance' => (float) $result['balance'],
                'outstanding' => (float) $result['outstanding'],
                'duplicate' => $result['duplicate'],
            ],
        ]);
    }

    public function show(Request $request, CyberBillingService $billing, CyberCreditService $credit)
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'max:16'],
            'device_id' => ['required', 'string', 'max:120'],
        ]);

        $subscriber = $billing->subscriberByDevice($data['sim_no'], $data['device_id']);
        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        return response()->json([
            'success' => true,
            'data' => $credit->status((int) $subscriber->id),
        ]);
    }
}
