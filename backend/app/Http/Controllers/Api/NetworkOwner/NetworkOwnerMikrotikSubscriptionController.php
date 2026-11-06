<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\AppSetting;
use App\Models\MikrotikPaymentRequest;
use App\Models\MikrotikPlan;
use App\Models\MikrotikSubscription;
use App\Models\User;
use App\Models\WalletLog;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

/**
 * MikroTik manager subscriptions — plans, entitlements, wallet
 * payments and manual-transfer requests.
 *
 * Financial safety: the wallet path debits `users.balance` under a
 * row lock inside a DB transaction and writes a plain 'debit'
 * WalletLog with reference_type='mikrotik_subscription' — the
 * existing customer flows (purchase/topup/transfer/advance) are
 * untouched; no new enum values or parallel ledgers.
 */
class NetworkOwnerMikrotikSubscriptionController extends Controller
{
    /** Every gateable key — mirrored from feature_keys.dart. */
    private const FEATURE_KEYS = [
        'mikrotik.connection', 'mikrotik.monitoring',
        'mikrotik.hotspot_users', 'mikrotik.voucher_cards',
        'mikrotik.card_templates', 'mikrotik.pppoe',
        'mikrotik.user_manager', 'mikrotik.profiles',
        'mikrotik.queues', 'mikrotik.firewall', 'mikrotik.nat',
        'mikrotik.network_tools', 'mikrotik.diagnostics',
        'mikrotik.system_admin', 'mikrotik.backup',
        'mikrotik.hotspot_pages', 'mikrotik.telegram',
        'mikrotik.remote_access',
    ];

    private function trialDays(): int
    {
        return max(1, (int) AppSetting::get('mikrotik.trial_days', 14));
    }

    private function enforce(): bool
    {
        return AppSetting::get('mikrotik.enforce', '0') === '1';
    }

    private function freeFeatures(): array
    {
        $raw = AppSetting::get('mikrotik.free_features', '[]');
        $decoded = is_array($raw) ? $raw : (json_decode($raw, true) ?: []);
        return array_values(array_intersect($decoded, self::FEATURE_KEYS));
    }

    private function currentSubscription(int $userId): ?MikrotikSubscription
    {
        return MikrotikSubscription::with('plan')
            ->where('user_id', $userId)
            ->whereIn('status', ['trial', 'active'])
            ->latest('ends_at')
            ->first();
    }

    /** Auto-start a free trial the first time an owner checks in. */
    private function ensureTrial(int $userId): MikrotikSubscription
    {
        $existing = $this->currentSubscription($userId);
        if ($existing) {
            return $existing;
        }
        // A historical expired sub → do not re-trial.
        $everHad = MikrotikSubscription::where('user_id', $userId)->exists();
        if ($everHad) {
            return MikrotikSubscription::where('user_id', $userId)
                ->latest('ends_at')->first();
        }
        return MikrotikSubscription::create([
            'user_id' => $userId,
            'plan_id' => null,
            'status' => 'trial',
            'starts_at' => now(),
            'ends_at' => now()->addDays($this->trialDays()),
        ]);
    }

    // ── Plans + entitlements ───────────────────────────────────────

    public function plans(): JsonResponse
    {
        $plans = MikrotikPlan::where('is_active', true)
            ->orderBy('sort_order')->orderBy('price')->get()
            ->map(fn($p) => [
                'id' => $p->id,
                'name' => $p->name,
                'description' => $p->description,
                'price' => (float) $p->price,
                'currency' => $p->currency,
                'duration_days' => $p->duration_days,
                'features' => $p->features ?? [],
            ]);

        return response()->json([
            'success' => true,
            'data' => $plans,
            'trial_days' => $this->trialDays(),
            'free_features' => $this->freeFeatures(),
            'enforce' => $this->enforce(),
        ]);
    }

    public function entitlements(Request $request): JsonResponse
    {
        $sub = $this->ensureTrial($request->user()->id);
        $running = $sub->is_running && in_array($sub->status, ['trial', 'active']);

        // Expired subs stay marked but report as expired.
        if (!$running && $sub->status !== 'expired') {
            $sub->update(['status' => 'expired']);
            $sub->refresh();
        }

        // Per-account overrides: grant opens keys beyond plan/free,
        // revoke withholds keys even on a running subscription.
        $granted = array_intersect(
            $sub->granted_features ?? [], self::FEATURE_KEYS);
        $revoked = array_intersect(
            $sub->revoked_features ?? [], self::FEATURE_KEYS);
        $base = $running ? self::FEATURE_KEYS : $this->freeFeatures();
        $features = array_values(array_diff(
            array_unique(array_merge($base, $granted)), $revoked));

        return response()->json([
            'success' => true,
            'enforce' => $this->enforce(),
            'status' => $sub->status,
            'trialing' => $running && $sub->status === 'trial',
            'active' => $running && $sub->status === 'active',
            'plan' => $sub->plan ? [
                'id' => $sub->plan->id,
                'name' => $sub->plan->name,
            ] : null,
            'starts_at' => $sub->starts_at?->toDateTimeString(),
            'trial_ends_at' => $sub->status === 'trial'
                ? $sub->ends_at?->toDateTimeString() : null,
            'ends_at' => $sub->ends_at?->toDateTimeString(),
            'trial_days' => $this->trialDays(),
            'features' => $features,
        ]);
    }

    // ── Wallet payment ─────────────────────────────────────────────

    public function subscribe(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'plan_id' => 'required|exists:mikrotik_plans,id',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $plan = MikrotikPlan::where('is_active', true)
            ->findOrFail($request->plan_id);
        $price = (float) $plan->price;

        try {
            $sub = DB::transaction(function () use ($request, $plan, $price) {
                $user = User::where('id', $request->user()->id)
                    ->lockForUpdate()->firstOrFail();

                if ((float) $user->balance < $price
                    || (float) $user->available_balance < $price) {
                    throw new \RuntimeException('الرصيد غير كافٍ لإتمام الاشتراك — اشحن المحفظة أولاً');
                }

                $before = (float) $user->balance;
                $user->decrement('balance', $price);
                $user->decrement('available_balance', $price);

                // Expire any running sub — the new one starts now.
                MikrotikSubscription::where('user_id', $user->id)
                    ->whereIn('status', ['trial', 'active'])
                    ->update(['status' => 'expired']);

                $sub = MikrotikSubscription::create([
                    'user_id' => $user->id,
                    'plan_id' => $plan->id,
                    'status' => 'active',
                    'starts_at' => now(),
                    'ends_at' => now()->addDays($plan->duration_days),
                ]);

                WalletLog::create([
                    'user_id' => $user->id,
                    'type' => 'debit',
                    'amount' => $price,
                    'balance_before' => $before,
                    'balance_after' => $before - $price,
                    'description' => "اشتراك MikroTik — {$plan->name} ({$plan->duration_days} يوم)",
                    'reference_type' => 'mikrotik_subscription',
                    'reference_id' => $sub->id,
                ]);

                return $sub;
            });
        } catch (\RuntimeException $e) {
            return response()->json(
                ['success' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم تفعيل اشتراكك بنجاح',
            'data' => [
                'id' => $sub->id,
                'status' => $sub->status,
                'ends_at' => $sub->ends_at?->toDateTimeString(),
            ],
        ]);
    }

    // ── Manual transfer requests (separate from wallet top-ups) ───

    public function paymentRequests(Request $request): JsonResponse
    {
        $rows = MikrotikPaymentRequest::with('plan:id,name')
            ->where('user_id', $request->user()->id)
            ->latest()
            ->get()
            ->map(fn($r) => [
                'id' => $r->id,
                'plan' => $r->plan?->name,
                'amount' => (float) $r->amount,
                'sender_name' => $r->sender_name,
                'status' => $r->status,
                'admin_note' => $r->admin_note,
                'created_at' => $r->created_at->toDateTimeString(),
            ]);

        return response()->json(['success' => true, 'data' => $rows]);
    }

    public function storePaymentRequest(Request $request): JsonResponse
    {
        // Same fields/workflow as wallet top-up, stored separately.
        $validator = Validator::make($request->all(), [
            'plan_id' => 'required|exists:mikrotik_plans,id',
            'sender_name' => 'required|string|max:255',
            'bank_account_id' => 'nullable|exists:bank_accounts,id',
            'transfer_receipt_number' => 'nullable|string|max:255',
            'receipt_image' => 'nullable|image|max:5120',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $plan = MikrotikPlan::where('is_active', true)
            ->findOrFail($request->plan_id);

        // One pending request at a time — avoids duplicate approvals.
        $pending = MikrotikPaymentRequest::where('user_id', $request->user()->id)
            ->where('status', 'pending')->exists();
        if ($pending) {
            return response()->json([
                'success' => false,
                'message' => 'لديك طلب دفع قيد المراجعة — انتظر الموافقة أولاً',
            ], 422);
        }

        $receiptImagePath = null;
        if ($request->hasFile('receipt_image')) {
            $receiptImagePath = $request->file('receipt_image')->store('receipt_images', 'public');
        }

        $req = MikrotikPaymentRequest::create([
            'user_id' => $request->user()->id,
            'plan_id' => $plan->id,
            'amount' => $plan->price,
            'sender_name' => $request->sender_name,
            'bank_account_id' => $request->bank_account_id,
            'transfer_receipt_number' => $request->transfer_receipt_number,
            'receipt_image' => $receiptImagePath,
        ]);

        try {
            $user = $request->user();
            $body = 'المستخدم ' . $user->name . ' يطلب اشتراك MikroTik — ' . $plan->name
                . ' بمبلغ ' . number_format((float) $plan->price) . ' ريال'
                . ' - اسم المودع: ' . $request->sender_name;
            if ($request->transfer_receipt_number) {
                $body .= ' - رقم السند: ' . $request->transfer_receipt_number;
            }
            if ($receiptImagePath) {
                $body .= ' - تم إرفاق صورة السند';
            }
            foreach (User::where('type', 'admin')->get() as $admin) {
                app(NotificationService::class)->send(
                    $admin,
                    'طلب اشتراك MikroTik',
                    $body,
                    ['type' => 'mikrotik_payment_request', 'user_id' => $user->id, 'request_id' => $req->id]
                );
            }
        } catch (\Throwable $e) {
            \Log::warning('MikroTik payment notification failed: ' . $e->getMessage());
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال طلب الدفع — سيُفعّل الاشتراك بعد مراجعة الإيصال',
            'data' => ['id' => $req->id, 'status' => $req->fresh()->status],
        ], 201);
    }
}
