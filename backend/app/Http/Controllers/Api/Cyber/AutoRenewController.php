<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Models\CyberSubscription;
use App\Services\CyberBillingService;
use Illuminate\Http\Request;

/**
 * PATCH /api/cyber/subscriptions/{subscription}/auto-renew (CYB-08).
 *
 * Toggles the auto_renew flag from the client app. Same device-bound
 * auth as the rest of the subscriber endpoints: the enrolled device
 * (sim_no + device_id against cyber_identities) is the credential —
 * a foreign device cannot arm another subscriber's renewal.
 */
class AutoRenewController extends Controller
{
    public function update(Request $request, CyberBillingService $billing, int $subscription)
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'max:16'],
            'device_id' => ['required', 'string', 'max:120'],
            'auto_renew' => ['required', 'boolean'],
        ]);

        try {
            $subscriber = $billing->subscriberByDevice($data['sim_no'], $data['device_id']);
        } catch (\Throwable $e) {
            $subscriber = null;
        }
        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        $target = CyberSubscription::where('id', $subscription)
            ->where('subscriber_id', $subscriber->id)
            ->first();
        if (! $target) {
            return response()->json([
                'success' => false,
                'message' => 'الاشتراك غير موجود',
            ], 404);
        }

        $target->forceFill(['auto_renew' => (bool) $data['auto_renew']])->save();

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $target->id,
                'auto_renew' => (bool) $target->auto_renew,
                'status' => $target->status,
                'ends_at' => $target->ends_at?->toIso8601String(),
            ],
        ]);
    }
}
