<?php

namespace App\Services;

use App\Events\CyberTransferCompleted;
use App\Models\CyberSubscriber;
use App\Models\CyberTransfer;
use App\Models\CyberWallet;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/**
 * CyberNet subscriber→subscriber balance transfer (CYB-06).
 *
 * transfer(): atomic debit+credit. Both wallets are locked inside one
 * transaction in ascending id order so two opposite transfers can't
 * deadlock. Idempotent on `idempotency_key` — a retried send returns
 * the original transfer without re-moving balance.
 *
 * The recipient's outstanding «سلفني» debt is collected from the
 * incoming amount first (same rule as agent top-ups), and both
 * parties get an FCM receipt: «حوّل لك 74XXXXXXX مبلغ X».
 */
class CyberTransferService
{
    public function __construct(
        private readonly CyberBillingService $billing,
        private readonly CyberCreditService $credit,
    ) {}

    /**
     * @return array{transfer: CyberTransfer, sender_balance: string, debt_collected: float, duplicate: bool}
     */
    public function transfer(CyberSubscriber $from, string $toSimNo, float $amount, string $idempotencyKey): array
    {
        $existing = CyberTransfer::where('idempotency_key', $idempotencyKey)->first();
        if ($existing) {
            return $this->result($existing, true);
        }

        $to = $this->billing->subscriberBySim($toSimNo);
        if ((int) $to->id === (int) $from->id) {
            throw CyberBillingException::selfTransfer();
        }

        $amount = round($amount, 2);

        // Resolve wallet rows up-front so both exist before locking.
        $fromWalletId = $this->billing->walletFor((int) $from->id)->id;
        $toWalletId = $this->billing->walletFor((int) $to->id)->id;
        $lockOrder = [$fromWalletId, $toWalletId];
        sort($lockOrder);

        $outcome = DB::transaction(function () use ($from, $to, $amount, $idempotencyKey, $fromWalletId, $toWalletId, $lockOrder) {
            // Lock both wallets in a fixed (ascending id) order.
            $wallets = [];
            foreach ($lockOrder as $walletId) {
                $wallets[$walletId] = CyberWallet::where('id', $walletId)->lockForUpdate()->firstOrFail();
            }
            $fromWallet = $wallets[$fromWalletId];
            $toWallet = $wallets[$toWalletId];

            if ((float) $fromWallet->balance < $amount) {
                throw CyberBillingException::insufficientFunds($amount, (float) $fromWallet->balance);
            }

            try {
                $transfer = CyberTransfer::create([
                    'from_subscriber_id' => $from->id,
                    'to_subscriber_id' => $to->id,
                    'from_sim_no' => $from->sim_no,
                    'to_sim_no' => $to->sim_no,
                    'amount' => $amount,
                    'currency' => 'YER',
                    'status' => CyberTransfer::STATUS_COMPLETED,
                    'idempotency_key' => $idempotencyKey,
                ]);
            } catch (QueryException $e) {
                // Lost the idempotency race — the other writer's row wins.
                return ['transfer' => CyberTransfer::where('idempotency_key', $idempotencyKey)->firstOrFail(), 'debt_collected' => 0.0];
            }

            $fromWallet->balance = (float) $fromWallet->balance - $amount;
            $toWallet->balance = (float) $toWallet->balance + $amount;

            // «سلفني» — the recipient's debt is collected from the
            // incoming credit first (mutates $toWallet->balance).
            $collected = $this->credit->collect((int) $to->id, $toWallet, 'transfer', (int) $transfer->id);

            $fromWallet->save();
            $toWallet->save();

            return ['transfer' => $transfer, 'debt_collected' => $collected];
        });

        $transfer = $outcome['transfer'];
        $duplicate = $transfer->wasRecentlyCreated === false;

        if (! $duplicate) {
            $senderBalance = (string) $this->billing->walletFor((int) $from->id)->balance;
            CyberTransferCompleted::dispatch($transfer, $senderBalance);
            $this->notifyParties($from, $to, $amount);
        }

        return $this->result($transfer, $duplicate, (float) $outcome['debt_collected']);
    }

    /**
     * «حوّل لك 74XXXXXXX مبلغ X ريال» to the recipient and a matching
     * debit receipt to the sender — both via the CYB-04
     * NotificationService token fan-out.
     */
    private function notifyParties(CyberSubscriber $from, CyberSubscriber $to, float $amount): void
    {
        $this->billing->notifySubscriber(
            $to,
            'سايبر نت',
            'حوّل لك '.$from->sim_no.' مبلغ '.number_format($amount).' ريال',
            [
                'type' => 'cyber_transfer_received',
                'amount' => (string) $amount,
                'from_sim_no' => (string) $from->sim_no,
            ]
        );

        $this->billing->notifySubscriber(
            $from,
            'سايبر نت',
            'حوّلت '.number_format($amount).' ريال إلى '.$to->sim_no,
            [
                'type' => 'cyber_transfer_sent',
                'amount' => (string) $amount,
                'to_sim_no' => (string) $to->sim_no,
            ]
        );
    }

    /**
     * @return array{transfer: CyberTransfer, sender_balance: string, debt_collected: float, duplicate: bool}
     */
    private function result(CyberTransfer $transfer, bool $duplicate, float $debtCollected = 0.0): array
    {
        return [
            'transfer' => $transfer,
            'sender_balance' => (string) $this->billing->walletFor((int) $transfer->from_subscriber_id)->balance,
            'debt_collected' => $debtCollected,
            'duplicate' => $duplicate,
        ];
    }
}
