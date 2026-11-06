<?php

namespace App\Services;

use App\Models\CyberCreditEvent;
use App\Models\CyberCreditLimit;
use App\Models\CyberSubscriber;
use App\Models\CyberWallet;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/**
 * CyberNet «سلفني» — subscriber credit (CYB-06).
 *
 * - borrow(): credits the wallet up to the subscriber's limit
 *   (config('cyber.credit.default_limit'), overridable per row in
 *   cyber_credit_limits). One open debt at a time — a second borrow
 *   is rejected until the outstanding amount is fully collected.
 * - collect(): called INSIDE the caller's wallet-locked transaction
 *   on every incoming credit (agent top-up via the CYB-06 hook in
 *   CyberBillingService::topup, or an incoming transfer via
 *   CyberTransferService). The debt is deducted from the incoming
 *   balance first; a partial collect leaves the rest outstanding.
 *
 * The cyber_credit_limits row is the serialisation point for
 * borrow/repay; it is created lazily so subscribers who never borrow
 * carry no credit state.
 */
class CyberCreditService
{
    public function __construct(
        private readonly CyberBillingService $billing,
    ) {}

    /**
     * Grant borrowed balance. Idempotent on $idempotencyKey when given.
     *
     * @return array{event: CyberCreditEvent, balance: string, outstanding: string, duplicate: bool}
     */
    public function borrow(CyberSubscriber $subscriber, float $amount, ?string $idempotencyKey = null): array
    {
        if ($idempotencyKey !== null
            && ($existing = CyberCreditEvent::where('idempotency_key', $idempotencyKey)->first())) {
            return $this->borrowResult($existing, true);
        }

        $amount = round($amount, 2);
        $wallet = $this->billing->walletFor((int) $subscriber->id);
        $limit = $this->limitFor((int) $subscriber->id);

        try {
            $event = DB::transaction(function () use ($subscriber, $wallet, $limit, $amount, $idempotencyKey) {
                $limit = CyberCreditLimit::where('id', $limit->id)->lockForUpdate()->firstOrFail();
                $wallet = CyberWallet::where('id', $wallet->id)->lockForUpdate()->firstOrFail();

                if ((float) $limit->outstanding > 0) {
                    throw CyberBillingException::outstandingDebt((float) $limit->outstanding);
                }
                if ($amount > (float) $limit->limit_amount) {
                    throw CyberBillingException::creditLimitExceeded((float) $limit->limit_amount, $amount);
                }

                try {
                    $event = CyberCreditEvent::create([
                        'subscriber_id' => $subscriber->id,
                        'sim_no' => $subscriber->sim_no,
                        'type' => CyberCreditEvent::TYPE_BORROW,
                        'amount' => $amount,
                        'outstanding_after' => $amount,
                        'idempotency_key' => $idempotencyKey,
                    ]);
                } catch (QueryException $e) {
                    // Lost the idempotency race — the other writer's row wins.
                    return CyberCreditEvent::where('idempotency_key', $idempotencyKey)->firstOrFail();
                }

                $limit->outstanding = $amount;
                $limit->save();

                $wallet->balance = (float) $wallet->balance + $amount;
                $wallet->save();

                return $event;
            });
        } catch (QueryException $e) {
            if ($idempotencyKey !== null
                && ($existing = CyberCreditEvent::where('idempotency_key', $idempotencyKey)->first())) {
                return $this->borrowResult($existing, true);
            }
            throw $e;
        }

        $duplicate = $event->wasRecentlyCreated === false;

        if (! $duplicate) {
            $this->billing->notifySubscriber(
                $subscriber,
                'سايبر نت — سلفني',
                'أُضيفت سلفة '.number_format($amount).' ريال إلى رصيدك — تُسدد تلقائياً من أول شحن أو تحويل وارد',
                [
                    'type' => 'cyber_credit_borrowed',
                    'amount' => (string) $amount,
                    'sim_no' => (string) $subscriber->sim_no,
                ]
            );
        }

        return $this->borrowResult($event, $duplicate);
    }

    /**
     * Collect outstanding debt from an incoming credit. Call ONLY
     * inside a transaction where $lockedWallet is already
     * lockForUpdate'd — it mutates the wallet balance in memory and
     * the caller persists it. Returns the amount collected (0 when
     * there is nothing to collect).
     */
    public function collect(int $subscriberId, CyberWallet $lockedWallet, string $source, ?int $sourceId = null): float
    {
        $limit = CyberCreditLimit::where('subscriber_id', $subscriberId)
            ->lockForUpdate()
            ->first();

        if (! $limit || (float) $limit->outstanding <= 0) {
            return 0.0;
        }

        $collected = round(min((float) $lockedWallet->balance, (float) $limit->outstanding), 2);
        if ($collected <= 0) {
            return 0.0;
        }

        $lockedWallet->balance = (float) $lockedWallet->balance - $collected;
        $limit->outstanding = round((float) $limit->outstanding - $collected, 2);
        $limit->save();

        $simNo = DB::table('cyber_subscribers')->where('id', $subscriberId)->value('sim_no');

        CyberCreditEvent::create([
            'subscriber_id' => $subscriberId,
            'sim_no' => $simNo,
            'type' => CyberCreditEvent::TYPE_REPAY,
            'amount' => $collected,
            'outstanding_after' => $limit->outstanding,
            'meta' => ['source' => $source, 'source_id' => $sourceId],
        ]);

        return $collected;
    }

    /**
     * The subscriber's live credit position for the client app.
     *
     * @return array{limit: float, outstanding: float, can_borrow: bool}
     */
    public function status(int $subscriberId): array
    {
        $limit = CyberCreditLimit::where('subscriber_id', $subscriberId)->first();
        $limitAmount = (float) ($limit?->limit_amount ?? config('cyber.credit.default_limit', 500));
        $outstanding = (float) ($limit?->outstanding ?? 0);

        return [
            'limit' => $limitAmount,
            'outstanding' => $outstanding,
            'can_borrow' => $outstanding <= 0 && $limitAmount > 0,
        ];
    }

    /**
     * The subscriber's credit row, created on first use with the
     * configured default limit.
     */
    public function limitFor(int $subscriberId): CyberCreditLimit
    {
        if ($limit = CyberCreditLimit::where('subscriber_id', $subscriberId)->first()) {
            return $limit;
        }

        try {
            return CyberCreditLimit::create([
                'subscriber_id' => $subscriberId,
                'limit_amount' => (float) config('cyber.credit.default_limit', 500),
                'outstanding' => 0,
            ]);
        } catch (QueryException $e) {
            return CyberCreditLimit::where('subscriber_id', $subscriberId)->firstOrFail();
        }
    }

    /**
     * @return array{event: CyberCreditEvent, balance: string, outstanding: string, duplicate: bool}
     */
    private function borrowResult(CyberCreditEvent $event, bool $duplicate): array
    {
        return [
            'event' => $event,
            'balance' => (string) $this->billing->walletFor((int) $event->subscriber_id)->balance,
            'outstanding' => (string) ($event->outstanding_after ?? 0),
            'duplicate' => $duplicate,
        ];
    }
}
