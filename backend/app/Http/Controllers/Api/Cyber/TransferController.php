<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Services\CyberBillingException;
use App\Services\CyberBillingService;
use App\Services\CyberTransferService;
use Illuminate\Http\Request;

/**
 * POST /api/cyber/transfer (CYB-06) — a subscriber sends balance to
 * another subscriber by SIM number. The sender authenticates through
 * the enrolled device (sim_no + device_id bound against
 * cyber_identities, same contract as the CYB-04 subscriber
 * endpoints): no users-account exists for subscribers.
 */
class TransferController extends Controller
{
    public function store(Request $request, CyberBillingService $billing, CyberTransferService $transfers)
    {
        $prefix = preg_quote((string) config('cyber.sim_prefix', '74'), '/');
        $simRule = ['required', 'string', 'regex:/^'.$prefix.'\d{7}$/'];

        $data = $request->validate([
            'sim_no' => $simRule,
            'device_id' => ['required', 'string', 'max:120'],
            'to_sim_no' => [...$simRule, 'different:sim_no'],
            'amount' => ['required', 'numeric', 'min:1', 'max:1000000'],
            'idempotency_key' => ['required', 'string', 'max:120'],
        ]);

        $sender = $billing->subscriberByDevice($data['sim_no'], $data['device_id']);
        if (! $sender) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        try {
            $result = $transfers->transfer(
                $sender,
                $data['to_sim_no'],
                (float) $data['amount'],
                $data['idempotency_key']
            );
        } catch (CyberBillingException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], $e->status);
        }

        $transfer = $result['transfer'];

        return response()->json([
            'success' => true,
            'data' => [
                'transfer_id' => $transfer->id,
                'from_sim_no' => $transfer->from_sim_no,
                'to_sim_no' => $transfer->to_sim_no,
                'amount' => (float) $transfer->amount,
                'currency' => $transfer->currency,
                'balance' => (float) $result['sender_balance'],
                'debt_collected' => $result['debt_collected'],
                'duplicate' => $result['duplicate'],
                'created_at' => $transfer->created_at?->toIso8601String(),
            ],
        ]);
    }
}
