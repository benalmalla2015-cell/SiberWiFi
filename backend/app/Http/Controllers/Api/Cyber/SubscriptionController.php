<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Services\CyberBillingException;
use App\Services\CyberBillingService;
use Illuminate\Http\Request;

/**
 * Subscriber-facing subscription endpoints (CYB-04).
 *
 * Subscribers own no users-account — the enrolled device IS the
 * credential: every call carries sim_no + device_id and is bound
 * against cyber_identities (CYB-03) by CyberBillingService::subscriberByDevice.
 *
 * POST /api/cyber/subscriptions         — activate a package
 * GET  /api/cyber/subscriptions/current — balance + live subscription
 */
class SubscriptionController extends Controller
{
    public function store(Request $request, CyberBillingService $billing)
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'max:16'],
            'device_id' => ['required', 'string', 'max:120'],
            'package_id' => ['required', 'integer', 'exists:cyber_packages,id'],
            'idempotency_key' => ['nullable', 'string', 'max:120'],
        ]);

        $subscriber = $this->resolveSubscriber($billing, $data['sim_no'], $data['device_id']);
        if (! $subscriber) {
            return $this->rejected();
        }

        try {
            $subscription = $billing->activate(
                (int) $subscriber->id,
                (int) $data['package_id'],
                $data['idempotency_key'] ?? null
            );
        } catch (CyberBillingException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], $e->status);
        }

        return response()->json([
            'success' => true,
            'data' => $this->payload($subscription, $billing),
        ]);
    }

    public function current(Request $request, CyberBillingService $billing)
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'max:16'],
            'device_id' => ['required', 'string', 'max:120'],
        ]);

        $subscriber = $this->resolveSubscriber($billing, $data['sim_no'], $data['device_id']);
        if (! $subscriber) {
            return $this->rejected();
        }

        $subscription = $billing->activeSubscription((int) $subscriber->id);

        return response()->json([
            'success' => true,
            'data' => [
                'balance' => (float) $billing->walletFor((int) $subscriber->id)->balance,
                'subscription' => $subscription ? $this->payload($subscription, $billing) : null,
            ],
        ]);
    }

    private function resolveSubscriber(CyberBillingService $billing, string $simNo, string $deviceId)
    {
        try {
            return $billing->subscriberByDevice($simNo, $deviceId);
        } catch (\Throwable $e) {
            return null;
        }
    }

    private function rejected()
    {
        return response()->json([
            'success' => false,
            'message' => 'الجهاز غير مرتبط بهذا الرقم',
        ], 403);
    }

    private function payload($subscription, CyberBillingService $billing): array
    {
        return [
            'id' => $subscription->id,
            'package_id' => $subscription->package_id,
            'starts_at' => $subscription->starts_at?->toIso8601String(),
            'ends_at' => $subscription->ends_at?->toIso8601String(),
            'data_limit_bytes' => $subscription->data_limit_bytes,
            'consumed_bytes' => $subscription->consumed_bytes,
            'status' => $subscription->status,
            'radius_reply' => $subscription->radius_reply,
            'balance' => (float) $billing->walletFor((int) $subscription->subscriber_id)->balance,
        ];
    }
}
