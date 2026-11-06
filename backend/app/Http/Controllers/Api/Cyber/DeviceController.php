<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Models\CyberSession;
use App\Models\CyberSubscriber;
use App\Models\CyberSubscription;
use App\Models\CyberTopup;
use App\Services\CyberBillingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Subscriber-device endpoints (CYB-05).
 *
 * The client app owns no users-account — its credential is the enrolled
 * device: sim_no + device_id bound against cyber_identities (CYB-03).
 *
 * POST /api/cyber/identity/bind — attach device_id + fcm_token to the
 * subscriber identity so CYB-04 top-up pushes reach this device.
 * Contract: {sim_no, device_id, fcm_token?} → {sim_no, device_id,
 * fcm_token_set, identity_status}. A different device_id than the one
 * stored is rejected 403 (anti-takeover); re-binding the same device is
 * idempotent. fcm_token lives on cyber_identities (CYB-04 migration
 * 000007) — it is optional so the bind still succeeds where Firebase
 * is unavailable.
 *
 * GET /api/cyber/activity — read-only transaction log for the device:
 * top-ups, subscription history, and RADIUS usage sessions.
 * Contract: ?sim_no&device_id → {topups[], subscriptions[], sessions[]}.
 */
class DeviceController extends Controller
{
    public function bind(Request $request, CyberBillingService $billing): JsonResponse
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'regex:/^74[0-9]{7}$/'],
            'device_id' => ['required', 'string', 'max:255'],
            'fcm_token' => ['nullable', 'string', 'max:512'],
        ]);

        $subscriber = CyberSubscriber::where('sim_no', $data['sim_no'])->first();
        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'رقم الشريحة غير موجود',
            ], 404);
        }

        $identity = $subscriber->identity
            ?? $subscriber->identity()->create(['status' => 'pending']);

        // Device takeover guard: once an identity carries a device_id only
        // that same device may refresh the binding.
        if ($identity->device_id !== null && $identity->device_id !== $data['device_id']) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        $identity->device_id = $data['device_id'];
        if (! empty($data['fcm_token'])) {
            $identity->fcm_token = $data['fcm_token'];
        }
        $identity->save();

        return response()->json([
            'success' => true,
            'data' => [
                'sim_no' => $subscriber->sim_no,
                'device_id' => $identity->device_id,
                'fcm_token_set' => $identity->fcm_token !== null,
                'identity_status' => $identity->status,
            ],
        ]);
    }

    public function activity(Request $request, CyberBillingService $billing): JsonResponse
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

        $topups = CyberTopup::where('subscriber_id', $subscriber->id)
            ->latest()
            ->limit(50)
            ->get()
            ->map(fn (CyberTopup $t) => [
                'id' => $t->id,
                'amount' => (float) $t->amount,
                'currency' => $t->currency,
                'status' => $t->status,
                'created_at' => $t->created_at?->toIso8601String(),
            ])
            ->values();

        $subscriptions = CyberSubscription::where('subscriber_id', $subscriber->id)
            ->with('package')
            ->latest()
            ->limit(50)
            ->get()
            ->map(fn (CyberSubscription $s) => [
                'id' => $s->id,
                'package_name' => $s->package?->name_ar ?: $s->package?->name,
                'price' => $s->package ? (float) $s->package->price : null,
                'starts_at' => $s->starts_at?->toIso8601String(),
                'ends_at' => $s->ends_at?->toIso8601String(),
                'data_limit_bytes' => $s->data_limit_bytes,
                'consumed_bytes' => $s->consumed_bytes,
                'status' => $s->status,
            ])
            ->values();

        $sessions = CyberSession::where('subscriber_id', $subscriber->id)
            ->latest('last_seen_at')
            ->limit(50)
            ->get()
            ->map(fn (CyberSession $s) => [
                'id' => $s->id,
                'nas_identifier' => $s->nas_identifier,
                'started_at' => $s->started_at?->toIso8601String(),
                'last_seen_at' => $s->last_seen_at?->toIso8601String(),
                'input_octets' => $s->input_octets,
                'output_octets' => $s->output_octets,
                'total_octets' => $s->total_octets,
                'status' => $s->status,
            ])
            ->values();

        return response()->json([
            'success' => true,
            'data' => [
                'topups' => $topups,
                'subscriptions' => $subscriptions,
                'sessions' => $sessions,
            ],
        ]);
    }

    /**
     * GET /api/cyber/identity/certificate — EAP-TLS provisioning payload.
     *
     * Returns the issued PKCS#12 bundle + CA cert (base64) for the
     * device-bound subscriber so the app can build a WPA2-Enterprise
     * WifiNetworkSuggestion without a manual certificate-install step.
     * Material is provisioned by ops under storage/app/cyber/certs/
     * ({sim}.p12 + ca.crt) — 404 while no bundle has been issued, in
     * which case the app falls back to an open suggestion.
     */
    public function certificate(Request $request, CyberBillingService $billing): JsonResponse
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'regex:/^74[0-9]{7}$/'],
            'device_id' => ['required', 'string', 'max:255'],
        ]);

        $subscriber = $billing->subscriberByDevice($data['sim_no'], $data['device_id']);
        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        $dir = config('cyber.cert.dir', 'cyber/certs');
        $p12 = "{$dir}/{$data['sim_no']}.p12";
        $ca = "{$dir}/ca.crt";

        if (! Storage::disk('local')->exists($p12) || ! Storage::disk('local')->exists($ca)) {
            return response()->json([
                'success' => false,
                'message' => 'الشهادة لم تصدر بعد',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'identity' => $data['sim_no'],
                'domain' => config('cyber.cert.domain', 'radius.cybernet.local'),
                'p12_base64' => base64_encode(Storage::disk('local')->get($p12)),
                'p12_password' => "cyber{$data['sim_no']}",
                'ca_base64' => base64_encode(Storage::disk('local')->get($ca)),
            ],
        ]);
    }

    /**
     * DELETE /api/cyber/account — permanent account deletion.
     *
     * Google Play compliance: the app lets subscribers create an
     * account, so it must also let them delete it. Authenticated by the
     * device credential (sim_no + device_id). Wipes personal data —
     * KYC document files and rows, device binding, FCM token and the
     * certificate identity — cancels active subscriptions, closes live
     * sessions, then soft-deletes the subscriber. Ledger rows (top-ups,
     * commissions, host shares) are kept for accounting integrity.
     */
    public function destroy(Request $request, CyberBillingService $billing): JsonResponse
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'regex:/^74[0-9]{7}$/'],
            'device_id' => ['required', 'string', 'max:255'],
        ]);

        $subscriber = $billing->subscriberByDevice($data['sim_no'], $data['device_id']);
        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        DB::transaction(function () use ($subscriber) {
            CyberSubscription::where('subscriber_id', $subscriber->id)
                ->where('status', 'active')
                ->update(['status' => 'cancelled']);

            CyberSession::where('subscriber_id', $subscriber->id)
                ->where('status', 'active')
                ->update([
                    'status' => 'closed',
                    'close_reason' => 'account_deleted',
                    'closed_at' => now(),
                ]);

            foreach ($subscriber->documents as $document) {
                if ($document->front_path) {
                    Storage::disk('local')->delete($document->front_path);
                }
                if ($document->back_path) {
                    Storage::disk('local')->delete($document->back_path);
                }
            }
            $subscriber->documents()->delete();

            $subscriber->identity?->update([
                'device_id' => null,
                'fcm_token' => null,
                'certificate_serial' => null,
                'status' => 'revoked',
            ]);

            $subscriber->delete();
        });

        return response()->json([
            'success' => true,
            'message' => 'تم حذف الحساب نهائياً',
        ]);
    }
}
