<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccPaymentRequest;
use App\Models\AccPlan;
use App\Models\AccSubscription;
use App\Models\AppSetting;
use App\Models\User;
use App\Models\WalletLog;
use App\Services\AccContext;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Accounting subscriptions — plans, entitlements, wallet payments
 * and manual-transfer requests (ACC-11, PLAN §6).
 *
 * Mirrors NetworkOwnerMikrotikSubscriptionController exactly, except
 * the subscription tenant is `network_owner_id` resolved by
 * AccContext — one plan covers the owner and every enrolled agent.
 *
 * Financial safety: the wallet path debits `users.balance` under a
 * row lock inside a DB transaction and writes a plain 'debit'
 * WalletLog with reference_type='acc_subscription' — the existing
 * customer flows (purchase/topup/transfer/advance) are untouched;
 * no new enum values or parallel ledgers.
 */
class AccBillingController extends Controller
{
    /** Every gateable acc.* key — mirrored from AccFeatures.all. */
    private const FEATURE_KEYS = [
        'acc.module', 'acc.dashboard', 'acc.inventory',
        'acc.categories', 'acc.sales', 'acc.pos_points',
        'acc.pos_orders', 'acc.agents', 'acc.network_devices',
        'acc.collections', 'acc.debts', 'acc.balances',
        'acc.expenses', 'acc.purchases', 'acc.returns',
        'acc.damaged', 'acc.discount_tiers', 'acc.cash_boxes',
        'acc.journal', 'acc.reports', 'acc.pos_analysis',
        'acc.audit_log', 'acc.sync_center', 'acc.backup',
        'acc.settings', 'acc.billing', 'acc.distributor',
        'acc.pos_app',
    ];

    private function trialDays(): int
    {
        return max(1, (int) AppSetting::get('acc.trial_days', 30));
    }

    private function enforce(): bool
    {
        return AppSetting::get('acc.enforce', '0') === '1';
    }

    private function freeFeatures(): array
    {
        $raw = AppSetting::get('acc.free_features', '[]');
        $decoded = is_array($raw) ? $raw : (json_decode($raw, true) ?: []);
        return array_values(array_intersect($decoded, self::FEATURE_KEYS));
    }

    private function currentSubscription(int $ownerId): ?AccSubscription
    {
        return AccSubscription::with('plan')
            ->where('network_owner_id', $ownerId)
            ->whereIn('status', ['trial', 'active'])
            ->latest('ends_at')
            ->first();
    }

    /** Auto-start a free trial the first time a tenant checks in. */
    private function ensureTrial(int $ownerId): AccSubscription
    {
        $existing = $this->currentSubscription($ownerId);
        if ($existing) {
            return $existing;
        }
        // A historical expired sub → do not re-trial.
        $everHad = AccSubscription::where('network_owner_id', $ownerId)->exists();
        if ($everHad) {
            return AccSubscription::where('network_owner_id', $ownerId)
                ->latest('ends_at')->first();
        }
        return AccSubscription::create([
            'network_owner_id' => $ownerId,
            'plan_id' => null,
            'status' => 'trial',
            'starts_at' => now(),
            'ends_at' => now()->addDays($this->trialDays()),
        ]);
    }

    // ── Plans + entitlements ───────────────────────────────────────

    public function plans(): JsonResponse
    {
        $plans = AccPlan::where('is_active', true)
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
            'pricing_note' => AppSetting::get('acc.pricing_note', ''),
        ]);
    }

    public function entitlements(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $sub = $this->ensureTrial($ctx->ownerId);
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
        $ctx = AccContext::fromRequest($request);

        $validator = Validator::make($request->all(), [
            'plan_id' => 'required|exists:acc_plans,id',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $plan = AccPlan::where('is_active', true)
            ->findOrFail($request->plan_id);
        $price = (float) $plan->price;

        try {
            $sub = DB::transaction(function () use ($ctx, $plan, $price) {
                // The acting account pays from its own wallet — same
                // semantics as the mikrotik flow.
                $user = User::where('id', $ctx->user->id)
                    ->lockForUpdate()->firstOrFail();

                if ((float) $user->balance < $price
                    || (float) $user->available_balance < $price) {
                    throw new \RuntimeException('الرصيد غير كافٍ لإتمام الاشتراك — اشحن المحفظة أولاً');
                }

                $before = (float) $user->balance;
                $user->decrement('balance', $price);
                $user->decrement('available_balance', $price);

                // Expire any running sub — the new one starts now.
                AccSubscription::where('network_owner_id', $ctx->ownerId)
                    ->whereIn('status', ['trial', 'active'])
                    ->update(['status' => 'expired']);

                $sub = AccSubscription::create([
                    'network_owner_id' => $ctx->ownerId,
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
                    'description' => "اشتراك المحاسبة — {$plan->name} ({$plan->duration_days} يوم)",
                    'reference_type' => 'acc_subscription',
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
        $ctx = AccContext::fromRequest($request);

        $rows = AccPaymentRequest::with('plan:id,name')
            ->where('network_owner_id', $ctx->ownerId)
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
        $ctx = AccContext::fromRequest($request);

        // Same fields/workflow as wallet top-up, stored separately.
        $validator = Validator::make($request->all(), [
            'plan_id' => 'required|exists:acc_plans,id',
            'sender_name' => 'required|string|max:255',
            'bank_account_id' => 'nullable|exists:bank_accounts,id',
            'transfer_receipt_number' => 'nullable|string|max:255',
            'receipt_image' => 'nullable|image|max:5120',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $plan = AccPlan::where('is_active', true)
            ->findOrFail($request->plan_id);

        // One pending request per tenant — avoids duplicate approvals.
        $pending = AccPaymentRequest::where('network_owner_id', $ctx->ownerId)
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

        $req = AccPaymentRequest::create([
            'network_owner_id' => $ctx->ownerId,
            'user_id' => $ctx->user->id,
            'plan_id' => $plan->id,
            'amount' => $plan->price,
            'sender_name' => $request->sender_name,
            'bank_account_id' => $request->bank_account_id,
            'transfer_receipt_number' => $request->transfer_receipt_number,
            'receipt_image' => $receiptImagePath,
        ]);

        try {
            $user = $ctx->user;
            $body = 'المستخدم ' . $user->name . ' يطلب اشتراك المحاسبة — ' . $plan->name
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
                    'طلب اشتراك المحاسبة',
                    $body,
                    ['type' => 'acc_payment_request', 'user_id' => $user->id, 'request_id' => $req->id]
                );
            }
        } catch (\Throwable $e) {
            \Log::warning('Accounting payment notification failed: ' . $e->getMessage());
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال طلب الدفع — سيُفعّل الاشتراك بعد مراجعة الإيصال',
            'data' => ['id' => $req->id, 'status' => $req->fresh()->status],
        ], 201);
    }
}
