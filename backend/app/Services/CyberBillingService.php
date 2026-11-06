<?php

namespace App\Services;

use App\Events\CyberTopupCompleted;
use App\Models\CyberPackage;
use App\Models\CyberSubscriber;
use App\Models\CyberSubscription;
use App\Models\CyberTopup;
use App\Models\CyberWallet;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * CyberNet billing core (CYB-04).
 *
 * - topup(): agent credits a subscriber by SIM number, idempotent on
 *   idempotency_key, then fires CyberTopupCompleted + the FCM
 *   "تم شحن رصيدك" notification through the existing
 *   NotificationService (read-only reuse of core infra).
 * - activate(): atomic wallet debit + subscription creation. The
 *   stored radius_reply is what CyberRadiusService hands to RADIUS
 *   at authorize time.
 * - Subscriber rows are owned by CYB-03 (cyber_subscribers); resolved
 *   here by sim_no through the query builder so this service never
 *   hard-depends on that track's model shape.
 */
class CyberBillingService
{
    /** Fallback when a package carries no explicit rate limit. */
    public const DEFAULT_RATE_LIMIT = '10M/10M';

    public function __construct(
        private readonly NotificationService $notifications,
    ) {}

    /**
     * Credit a subscriber wallet. Returns the persisted top-up, the
     * resulting balance, and whether the call was an idempotent retry.
     *
     * @return array{topup: CyberTopup, balance: string, duplicate: bool}
     */
    public function topup(int $agentId, string $simNo, float $amount, string $idempotencyKey): array
    {
        $existing = CyberTopup::where('idempotency_key', $idempotencyKey)->first();
        if ($existing) {
            return [
                'topup' => $existing,
                'balance' => (string) $this->walletFor((int) $existing->subscriber_id)->balance,
                'duplicate' => true,
            ];
        }

        $subscriber = $this->subscriberBySim($simNo);
        $amount = round($amount, 2);

        $topup = DB::transaction(function () use ($agentId, $subscriber, $simNo, $amount, $idempotencyKey) {
            // Lock the wallet row inside the transaction so concurrent
            // credits/debits serialise on it.
            $wallet = CyberWallet::where('id', $this->walletFor((int) $subscriber->id)->id)
                ->lockForUpdate()
                ->firstOrFail();

            try {
                $topup = CyberTopup::create([
                    'agent_id' => $agentId,
                    'subscriber_id' => $subscriber->id,
                    'sim_no' => $simNo,
                    'amount' => $amount,
                    'currency' => 'YER',
                    'status' => 'completed',
                    'idempotency_key' => $idempotencyKey,
                ]);
            } catch (QueryException $e) {
                // Lost the idempotency race — the other writer's row wins.
                return CyberTopup::where('idempotency_key', $idempotencyKey)->firstOrFail();
            }

            $wallet->balance = (float) $wallet->balance + $amount;

            // CYB-06 addition: an outstanding «سلفني» debt is collected
            // from the incoming credit first, inside this same locked
            // transaction. Resolved lazily to keep the service graph
            // acyclic (credit → billing reuse).
            app(CyberCreditService::class)->collect(
                (int) $subscriber->id, $wallet, 'topup', (int) $topup->id
            );

            $wallet->save();

            return $topup;
        });

        $balanceAfter = (string) $this->walletFor((int) $topup->subscriber_id)->balance;
        $wasDuplicate = $topup->wasRecentlyCreated === false;

        if (! $wasDuplicate) {
            CyberTopupCompleted::dispatch($topup, $balanceAfter);
            $this->notifyTopup($subscriber, $amount);
        }

        return ['topup' => $topup, 'balance' => $balanceAfter, 'duplicate' => $wasDuplicate];
    }

    /**
     * Activate a package: atomic debit + subscription window. Safe to
     * retry with the same idempotency key.
     */
    public function activate(int $subscriberId, int $packageId, ?string $idempotencyKey = null): CyberSubscription
    {
        if ($idempotencyKey !== null) {
            $existing = CyberSubscription::where('idempotency_key', $idempotencyKey)->first();
            if ($existing) {
                return $existing;
            }
        }

        $package = CyberPackage::active()->findOrFail($packageId);

        try {
            return DB::transaction(function () use ($subscriberId, $package, $idempotencyKey) {
                $wallet = CyberWallet::where('subscriber_id', $subscriberId)
                    ->lockForUpdate()
                    ->first();
                $wallet ??= CyberWallet::where('id', $this->walletFor($subscriberId)->id)
                    ->lockForUpdate()
                    ->first();

                $balance = (float) ($wallet?->balance ?? 0);
                if ($balance < (float) $package->price) {
                    throw CyberBillingException::insufficientBalance((float) $package->price, $balance);
                }

                $wallet->balance = $balance - (float) $package->price;
                $wallet->save();

                $startsAt = now();
                $endsAt = $startsAt->copy()->addDays($package->duration_days);
                $dataLimitBytes = $package->data_limit_bytes;

                return CyberSubscription::create([
                    'subscriber_id' => $subscriberId,
                    'package_id' => $package->id,
                    'starts_at' => $startsAt,
                    'ends_at' => $endsAt,
                    'data_limit_bytes' => $dataLimitBytes,
                    'consumed_bytes' => 0,
                    'status' => CyberSubscription::STATUS_ACTIVE,
                    'radius_reply' => $this->buildRadiusReply($package, $endsAt, $dataLimitBytes),
                    'idempotency_key' => $idempotencyKey,
                ]);
            });
        } catch (QueryException $e) {
            // Unique idempotency_key race — return the winning row.
            if ($idempotencyKey !== null
                && ($existing = CyberSubscription::where('idempotency_key', $idempotencyKey)->first())) {
                return $existing;
            }
            throw $e;
        }
    }

    /**
     * The stored-reply → RADIUS translation. Authorize-time values are
     * recomputed live by CyberRadiusService::authorize(); what is
     * stored here is the activation snapshot.
     */
    public function buildRadiusReply(CyberPackage $package, $endsAt, ?int $dataLimitBytes): array
    {
        $reply = [
            'Mikrotik-Rate-Limit' => $package->rate_limit ?: self::DEFAULT_RATE_LIMIT,
            'Session-Timeout' => max(0, now()->diffInSeconds($endsAt, false)),
        ];
        if ($dataLimitBytes !== null) {
            $reply['Mikrotik-Total-Limit'] = $dataLimitBytes;
        }

        return $reply;
    }

    public function packages()
    {
        return CyberPackage::active()->get();
    }

    public function walletFor(int $subscriberId): CyberWallet
    {
        if ($wallet = CyberWallet::where('subscriber_id', $subscriberId)->first()) {
            return $wallet;
        }

        try {
            return CyberWallet::create([
                'subscriber_id' => $subscriberId, 'balance' => 0, 'currency' => 'YER',
            ]);
        } catch (QueryException $e) {
            // Concurrent first credit — the other writer's wallet wins.
            return CyberWallet::where('subscriber_id', $subscriberId)->firstOrFail();
        }
    }

    /**
     * The active subscription for a subscriber, if any.
     */
    public function activeSubscription(int $subscriberId): ?CyberSubscription
    {
        return CyberSubscription::where('subscriber_id', $subscriberId)
            ->where('status', CyberSubscription::STATUS_ACTIVE)
            ->latest('ends_at')
            ->first();
    }

    /**
     * Resolve a cyber_subscribers row by SIM number (CYB-03 contract:
     * cyber_subscribers.sim_no holds the 74XXXXXXX number).
     */
    public function subscriberBySim(string $simNo): CyberSubscriber
    {
        if (! Schema::hasTable('cyber_subscribers')) {
            throw CyberBillingException::subscribersModuleMissing();
        }

        $subscriber = CyberSubscriber::where('sim_no', $simNo)->first();
        if (! $subscriber) {
            throw CyberBillingException::subscriberNotFound($simNo);
        }

        return $subscriber;
    }

    /**
     * Device-bound subscriber lookup: the client has no users-account —
     * its identity is the enrolled device (cyber_identities.device_id).
     * Any non-revoked identity owning that device authenticates the sim.
     */
    public function subscriberByDevice(string $simNo, string $deviceId): ?CyberSubscriber
    {
        if (! Schema::hasTable('cyber_subscribers') || ! Schema::hasTable('cyber_identities')) {
            return null;
        }

        return CyberSubscriber::where('sim_no', $simNo)
            ->whereHas('identity', function ($q) use ($deviceId) {
                $q->where('device_id', $deviceId)->where('status', '!=', 'revoked');
            })
            ->first();
    }

    /**
     * "تم شحن رصيدك بـX ريال" — pushed to the subscriber's enrolled
     * devices (cyber_identities.fcm_token) through the existing
     * NotificationService::sendToTokens (read-only reuse of core infra).
     * A users-linked send() is kept for the future case where a
     * subscriber also owns an app account.
     */
    private function notifyTopup(object $subscriber, float $amount): void
    {
        $this->notifySubscriber(
            $subscriber,
            'سايبر نت',
            'تم شحن رصيدك بـ'.number_format($amount).' ريال',
            [
                'type' => 'cyber_topup',
                'amount' => (string) $amount,
                'sim_no' => (string) ($subscriber->sim_no ?? ''),
            ]
        );
    }

    /**
     * CYB-06 addition (public so the transfer/credit services reuse the
     * same token fan-out): push a notification to every enrolled device
     * of a subscriber (cyber_identities.fcm_token) through the existing
     * NotificationService::sendToTokens. The users-linked send() is
     * kept for the future case where a subscriber also owns an app
     * account. Never throws — failures are logged.
     */
    public function notifySubscriber(object $subscriber, string $title, string $body, array $data = []): void
    {
        try {
            $tokens = Schema::hasTable('cyber_identities')
                ? DB::table('cyber_identities')
                    ->where('subscriber_id', $subscriber->id)
                    ->where('status', '!=', 'revoked')
                    ->whereNotNull('fcm_token')
                    ->pluck('fcm_token')
                    ->all()
                : [];

            if ($tokens !== []) {
                $this->notifications->sendToTokens($tokens, $title, $body, $data, null, 'customer_app');
            }

            if (($userId = $subscriber->user_id ?? null) && ($user = User::find($userId))) {
                $this->notifications->send($user, $title, $body, $data);
            }
        } catch (\Throwable $e) {
            Log::warning('CyberNet top-up notification failed: '.$e->getMessage());
        }
    }
}
