<?php

namespace App\Services;

use App\Models\CyberSubscription;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * CyberNet auto-renewal sweep (CYB-08).
 *
 * Subscriptions flagged auto_renew are renewed one day before ends_at:
 * the wallet debit goes through CyberBillingService::activate() (the
 * same atomic row-locked path as manual activation — called, never
 * duplicated) under the idempotency key "auto-renew-{subscription_id}"
 * so re-running the sweep can never charge twice.
 *
 * The renewed window CHAINS onto the old subscription's tail
 * (starts_at = old ends_at) so the subscriber keeps the paid day the
 * sweep ran ahead of; authorize() already prefers the row with the
 * latest ends_at, so service simply continues under the new quota.
 *
 * Outcomes are pushed to the subscriber's enrolled devices
 * (cyber_identities.fcm_token) — the subscriber owns no users-account:
 *   success → «تجددت باقتك»
 *   failure → «رصيد غير كافٍ لتجديد باقتك — اشحن قبل انتهائها»
 */
class CyberAutoRenewService
{
    /** How far ahead of ends_at the renewal fires. */
    public const RENEW_HORIZON_HOURS = 24;

    public function __construct(
        private readonly CyberBillingService $billing,
        private readonly NotificationService $notifications,
    ) {}

    /**
     * Renew every auto_renew subscription expiring within the horizon.
     *
     * @return array{renewed: int, failed: int, skipped: int}
     */
    public function renewDue(): array
    {
        $stats = ['renewed' => 0, 'failed' => 0, 'skipped' => 0];

        $due = CyberSubscription::where('status', CyberSubscription::STATUS_ACTIVE)
            ->where('auto_renew', true)
            ->where('ends_at', '>', now())
            ->where('ends_at', '<=', now()->addHours(self::RENEW_HORIZON_HOURS))
            ->get();

        foreach ($due as $subscription) {
            $result = $this->renewOne($subscription);
            $stats[$result]++;
        }

        return $stats;
    }

    /**
     * @return 'renewed'|'failed'|'skipped'
     */
    private function renewOne(CyberSubscription $subscription): string
    {
        $idempotencyKey = 'auto-renew-'.$subscription->id;

        try {
            $renewal = $this->billing->activate(
                (int) $subscription->subscriber_id,
                (int) $subscription->package_id,
                $idempotencyKey
            );
        } catch (CyberBillingException $e) {
            $this->notify($subscription, 'رصيد غير كافٍ لتجديد باقتك — اشحن قبل انتهائها', 'cyber_renew_failed');

            return 'failed';
        } catch (\Throwable $e) {
            Log::warning("CyberNet auto-renew #{$subscription->id} failed: ".$e->getMessage());

            return 'failed';
        }

        if (! $renewal->wasRecentlyCreated) {
            // A previous sweep already chained this renewal.
            return 'skipped';
        }

        // Chain the new window onto the old tail and refresh the stored
        // authorize snapshot through the billing service's own builder.
        $package = $renewal->package;
        $startsAt = $subscription->ends_at->copy();
        $endsAt = $startsAt->copy()->addDays((int) $package->duration_days);

        $renewal->update([
            'starts_at' => $startsAt,
            'ends_at' => $endsAt,
            'radius_reply' => $this->billing->buildRadiusReply(
                $package, $endsAt, $renewal->data_limit_bytes
            ),
        ]);

        $this->notify($subscription, 'تجددت باقتك', 'cyber_renewed', [
            'package' => (string) ($package->name_ar ?? $package->name),
            'ends_at' => $endsAt->toIso8601String(),
        ]);

        return 'renewed';
    }

    /**
     * Push the outcome to the subscriber's enrolled devices
     * (cyber_identities.fcm_token) via the existing NotificationService
     * — same channel CYB-04 top-up receipts use.
     */
    private function notify(CyberSubscription $subscription, string $body, string $type, array $extra = []): void
    {
        $data = array_merge([
            'type' => $type,
            'subscription_id' => (string) $subscription->id,
        ], $extra);

        try {
            $tokens = Schema::hasTable('cyber_identities')
                ? DB::table('cyber_identities')
                    ->where('subscriber_id', $subscription->subscriber_id)
                    ->where('status', '!=', 'revoked')
                    ->whereNotNull('fcm_token')
                    ->pluck('fcm_token')
                    ->all()
                : [];

            if ($tokens !== []) {
                $this->notifications->sendToTokens($tokens, 'سايبر نت', $body, $data, null, 'customer_app');
            }

            if (Schema::hasColumn('cyber_subscribers', 'user_id')) {
                $userId = DB::table('cyber_subscribers')
                    ->where('id', $subscription->subscriber_id)
                    ->value('user_id');
                if ($userId && ($user = User::find($userId))) {
                    $this->notifications->send($user, 'سايبر نت', $body, $data);
                }
            }
        } catch (\Throwable $e) {
            Log::warning('CyberNet auto-renew notification failed: '.$e->getMessage());
        }
    }
}
