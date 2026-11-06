<?php

namespace App\Services;

use App\Models\AccAccount;
use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\AccCashBox;
use App\Models\AccCashTransfer;
use App\Models\AccCollection;
use App\Models\AccDebt;
use App\Models\AccDebtPayment;
use App\Models\AccExpense;
use App\Models\AccExpenseCategory;
use App\Models\AccPosPoint;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/**
 * ACC-05 — the money-movement document cycle (PLAN §2.3 + §3).
 *
 * Every operation is ONE atomic DB transaction that produces a
 * balanced journal entry through AccPostingService:
 *
 *   collect()    Dr cash box / Cr party receivable        (collection)
 *   createDebt() Dr AR / Cr equity  — or Dr equity / Cr AP
 *                for supplier payables                    (adjustment)
 *   payDebt()    receivable: collection row + Dr box / Cr AR
 *                payable:    Dr AP / Cr box               (collection)
 *   transfer()   Dr to-box / Cr from-box                  (transfer)
 *   expense()    Dr expenses / Cr cash box                (expense)
 *   voidExpense() reversal entry + box refund             (expense)
 *
 * Currency rule (PLAN §2.5): documents carry their own
 * `currency`/`exchange_rate`, but acc_balances is single-currency,
 * so every journal line posts the north-normalized `base_amount`
 * via CurrencyService — read-only on exchange_rate_settings.
 * Cash-box balances are kept in each box's own currency.
 */
class AccMoneyService
{
    /** The journal's base denomination (platform convention). */
    private const BASE_CURRENCY = 'north';

    public function __construct(private AccPostingService $posting) {}

    // ── Collections (money in) ───────────────────────────────────

    /**
     * Record a cash collection and post its entry.
     * Payload: party_type, party_id?, party_name?, phone?, amount,
     * currency?, cash_box_id?, collected_at?, note?, idempotency_key?
     */
    public function collect(AccContext $ctx, array $data): AccCollection
    {
        $key = $this->idempotencyKey($data);
        if ($key !== null) {
            $existing = AccCollection::where('idempotency_key', $key)->first();
            if ($existing) {
                return $existing;
            }
        }

        [$partyType, $partyId, $account, $partyName] = $this->resolveParty(
            $ctx,
            (string) ($data['party_type'] ?? ''),
            $data['party_id'] ?? null,
            $data['party_name'] ?? null,
            AccCollection::PARTY_TYPES
        );

        $amount = $this->positiveAmount($data['amount'] ?? null, 'مبلغ التحصيل');
        $currency = $this->currency($data['currency'] ?? null);

        $attempts = 0;
        do {
            try {
                return DB::transaction(function () use (
                    $ctx, $data, $key, $partyType, $partyId, $account, $partyName, $amount, $currency
                ) {
                    $box = $this->resolveBox($ctx, $data['cash_box_id'] ?? null, $currency);
                    $base = $this->toBase($amount, $currency);

                    $collection = AccCollection::create([
                        'network_owner_id' => $ctx->ownerId,
                        'collector_agent_id' => $ctx->agentId(),
                        'party_type' => $partyType,
                        'party_id' => $partyId,
                        'party_name' => $partyName,
                        'phone' => $data['phone'] ?? null,
                        'amount' => $amount,
                        'currency' => $currency,
                        'exchange_rate' => $this->rateToBase($currency),
                        'base_amount' => $base,
                        'cash_box_id' => $box->id,
                        'collected_at' => $this->timestamp($data['collected_at'] ?? null),
                        'note' => $data['note'] ?? null,
                        'idempotency_key' => $key,
                    ]);

                    // Journal side: 'person' books as a named customer
                    // balance; unnamed parties pool under customer:0.
                    $entry = $this->posting->post('collection', [
                        'network_owner_id' => $ctx->ownerId,
                        'agent_id' => $ctx->agentId(),
                        'doc_ref_id' => $collection->id,
                        'memo' => 'تحصيل من ' . $partyName,
                        'idempotency_key' => 'collection-' . $collection->id,
                        'lines' => [
                            $this->leg(AccAccount::CASH_MAIN, 'box', $box->id, $base, 0),
                            $this->leg(
                                $account,
                                $partyType === 'person' ? 'customer' : $partyType,
                                $partyId ?? 0,
                                0,
                                $base
                            ),
                        ],
                    ]);

                    $this->addToBox($box, $this->toBoxAmount($amount, $currency, $box));
                    $collection->journal_entry_id = $entry->id;
                    $collection->save();

                    $this->audit($ctx, 'collection.create', 'acc_collections', $collection->id, [
                        'party' => "{$partyType}:{$partyId}",
                        'amount' => $amount,
                        'currency' => $currency,
                        'base' => $base,
                        'box' => $box->id,
                    ]);

                    return $collection;
                });
            } catch (QueryException $e) {
                if ($key !== null) {
                    $existing = AccCollection::where('idempotency_key', $key)->first();
                    if ($existing) {
                        return $existing;
                    }
                }
                if (++$attempts >= 3 || ! $this->isUniqueViolation($e)) {
                    throw $e;
                }
            }
        } while (true);
    }

    // ── Debts (receivables + payables) ───────────────────────────

    /**
     * Register a debt. `post_entry` (default true) books the opening
     * receivable/payable against equity — turn it off when the debt
     * already exists in the books (e.g. a credit sale posted its AR).
     */
    public function createDebt(AccContext $ctx, array $data): AccDebt
    {
        $types = AccDebt::PARTY_TYPES;
        $amount = $this->positiveAmount($data['amount_due'] ?? null, 'مبلغ الدين');
        $currency = $this->currency($data['currency'] ?? null);
        $postEntry = (bool) ($data['post_entry'] ?? true);

        return DB::transaction(function () use (
            $ctx, $data, $types, $amount, $currency, $postEntry
        ) {
            [$partyType, $partyId, $account, $partyName] = $this->resolveParty(
                $ctx,
                (string) ($data['party_type'] ?? ''),
                $data['party_id'] ?? null,
                $data['party_name'] ?? null,
                $types
            );

            $debt = AccDebt::create([
                'network_owner_id' => $ctx->ownerId,
                'party_type' => $partyType,
                'party_id' => $partyId,
                'party_name' => $partyName,
                'phone' => $data['phone'] ?? null,
                'amount_due' => $amount,
                'amount_paid' => 0,
                'base_due' => $this->toBase($amount, $currency),
                'base_paid' => 0,
                'currency' => $currency,
                'exchange_rate' => $this->rateToBase($currency),
                'status' => AccDebt::STATUS_OPEN,
                'due_date' => $data['due_date'] ?? null,
                'agent_id' => $ctx->agentId(),
                'note' => $data['note'] ?? null,
            ]);

            // Named parties (customer/person) self-reference so each
            // debt tracks its own acc_balances line.
            if ($partyId === null) {
                $debt->party_id = $debt->id;
                $debt->save();
            }

            if ($postEntry) {
                $journalParty = $this->journalParty($debt);
                $base = (float) $debt->base_due;
                $entry = $this->posting->post('adjustment', [
                    'network_owner_id' => $ctx->ownerId,
                    'agent_id' => $ctx->agentId(),
                    'doc_ref_id' => $debt->id,
                    'memo' => ($debt->isPayable() ? 'دين مستحق لـ ' : 'دين على ') . $partyName,
                    'idempotency_key' => 'debt-' . $debt->id . '-open',
                    'lines' => $debt->isPayable()
                        ? [
                            $this->leg(AccAccount::EQUITY, null, null, $base, 0),
                            $this->leg(AccAccount::AP_SUPPLIERS, $journalParty[0], $journalParty[1], 0, $base),
                        ]
                        : [
                            $this->leg($account, $journalParty[0], $journalParty[1], $base, 0),
                            $this->leg(AccAccount::EQUITY, null, null, 0, $base),
                        ],
                ]);
                $debt->journal_entry_id = $entry->id;
                $debt->save();
            }

            $this->audit($ctx, 'debt.create', 'acc_debts', $debt->id, [
                'party' => "{$partyType}:{$debt->party_id}",
                'due' => $amount,
                'currency' => $currency,
                'posted' => $postEntry,
            ]);

            return $debt;
        });
    }

    /**
     * Settle (part of) a debt atomically: payment row + collection
     * (receivable side) + journal entry + debt status flip.
     */
    public function payDebt(AccContext $ctx, int $debtId, array $data): AccDebtPayment
    {
        $amount = $this->positiveAmount($data['amount'] ?? null, 'مبلغ السداد');

        return DB::transaction(function () use ($ctx, $debtId, $data, $amount) {
            $debt = AccDebt::where('network_owner_id', $ctx->ownerId)
                ->lockForUpdate()
                ->find($debtId);
            if ($debt === null) {
                throw new AccMoneyException('الدين غير موجود', 404);
            }
            if ($debt->status === AccDebt::STATUS_PAID) {
                throw new AccMoneyException('الدين مسدد بالكامل', 409);
            }
            if ($amount > $debt->remaining() + 0.005) {
                throw new AccMoneyException(
                    'المبلغ أكبر من المتبقي — المتبقي ' . $debt->remaining()
                );
            }

            $currency = $debt->currency;
            $box = $this->resolveBox($ctx, $data['cash_box_id'] ?? null, $currency);
            $base = $this->toBase($amount, $currency);
            [$journalType, $journalId] = $this->journalParty($debt);
            $boxDelta = $this->toBoxAmount($amount, $currency, $box);
            $payable = $debt->isPayable();

            // Payables leave the box — the drawer must hold the cash.
            if ($payable && (float) $box->balance < $boxDelta - 0.005) {
                throw new AccMoneyException(
                    "رصيد الصندوق غير كافٍ — المتاح {$box->balance} والمطلوب {$boxDelta}"
                );
            }

            $collection = null;
            if (! $payable) {
                $collection = AccCollection::create([
                    'network_owner_id' => $ctx->ownerId,
                    'collector_agent_id' => $ctx->agentId(),
                    'party_type' => $debt->party_type === 'person' ? 'person' : $debt->party_type,
                    'party_id' => $debt->party_id,
                    'party_name' => $debt->party_name,
                    'phone' => $debt->phone,
                    'amount' => $amount,
                    'currency' => $currency,
                    'exchange_rate' => $this->rateToBase($currency),
                    'base_amount' => $base,
                    'cash_box_id' => $box->id,
                    'debt_id' => $debt->id,
                    'collected_at' => $this->timestamp($data['paid_at'] ?? null),
                    'note' => $data['note'] ?? null,
                ]);
            }

            $account = $payable
                ? AccAccount::AP_SUPPLIERS
                : $this->receivableAccount($debt->party_type);
            $entry = $this->posting->post('collection', [
                'network_owner_id' => $ctx->ownerId,
                'agent_id' => $ctx->agentId(),
                'doc_ref_id' => $debt->id,
                'memo' => ($payable ? 'سداد دين لـ ' : 'سداد دين على ') . $debt->party_name,
                'idempotency_key' => 'debt-' . $debt->id . '-pay-' . ($debt->payments()->count() + 1),
                'lines' => $payable
                    ? [
                        $this->leg($account, $journalType, $journalId, $base, 0),
                        $this->leg(AccAccount::CASH_MAIN, 'box', $box->id, 0, $base),
                    ]
                    : [
                        $this->leg(AccAccount::CASH_MAIN, 'box', $box->id, $base, 0),
                        $this->leg($account, $journalType, $journalId, 0, $base),
                    ],
            ]);

            $this->addToBox($box, $payable ? -$boxDelta : $boxDelta);

            $payment = AccDebtPayment::create([
                'network_owner_id' => $ctx->ownerId,
                'debt_id' => $debt->id,
                'collection_id' => $collection?->id,
                'amount' => $amount,
                'base_amount' => $base,
                'cash_box_id' => $box->id,
                'journal_entry_id' => $entry->id,
                'agent_id' => $ctx->agentId(),
                'paid_at' => $this->timestamp($data['paid_at'] ?? null),
                'note' => $data['note'] ?? null,
            ]);

            if ($collection !== null) {
                $collection->journal_entry_id = $entry->id;
                $collection->save();
            }

            $debt->amount_paid = (float) $debt->amount_paid + $amount;
            $debt->base_paid = (float) $debt->base_paid + $base;
            $debt->status = $debt->remaining() <= 0.005
                ? AccDebt::STATUS_PAID
                : AccDebt::STATUS_PARTIAL;
            $debt->save();

            $this->audit($ctx, 'debt.pay', 'acc_debts', $debt->id, [
                'payment_id' => $payment->id,
                'amount' => $amount,
                'remaining' => $debt->remaining(),
            ]);

            return $payment;
        });
    }

    // ── Cash boxes + transfers ───────────────────────────────────

    /**
     * Create a box; a positive opening balance books Dr box /
     * Cr equity so acc_balances never diverges from the drawer.
     */
    public function createBox(AccContext $ctx, array $data): AccCashBox
    {
        $name = trim((string) ($data['name'] ?? ''));
        if ($name === '') {
            throw new AccMoneyException('اسم الصندوق مطلوب');
        }
        $opening = round((float) ($data['opening_balance'] ?? 0), 2);
        if ($opening < 0) {
            throw new AccMoneyException('الرصيد الافتتاحي لا يكون سالباً');
        }

        return DB::transaction(function () use ($ctx, $name, $data, $opening) {
            $exists = AccCashBox::where('network_owner_id', $ctx->ownerId)
                ->where('name', $name)
                ->exists();
            if ($exists) {
                throw new AccMoneyException('يوجد صندوق بهذا الاسم', 409);
            }

            $box = AccCashBox::create([
                'network_owner_id' => $ctx->ownerId,
                'name' => $name,
                'currency' => in_array($data['currency'] ?? null, ['north', 'south'], true)
                    ? $data['currency'] : self::BASE_CURRENCY,
                'balance' => 0,
                'is_default' => false,
                'is_active' => true,
            ]);

            if ($opening > 0) {
                $entry = $this->posting->post('adjustment', [
                    'network_owner_id' => $ctx->ownerId,
                    'agent_id' => $ctx->agentId(),
                    'doc_ref_id' => $box->id,
                    'memo' => 'رصيد افتتاحي لصندوق «' . $name . '»',
                    'idempotency_key' => 'cashbox-' . $box->id . '-open',
                    'lines' => [
                        $this->leg(
                            AccAccount::CASH_MAIN, 'box', $box->id,
                            $this->toBase($opening, $box->currency), 0
                        ),
                        $this->leg(
                            AccAccount::EQUITY, null, null,
                            0, $this->toBase($opening, $box->currency)
                        ),
                    ],
                ]);
                $box->balance = $opening;
                $box->save();
            }

            $this->audit($ctx, 'cashbox.create', 'acc_cash_boxes', $box->id, [
                'name' => $name, 'opening' => $opening,
            ]);

            return $box;
        });
    }


    /**
     * Move cash between two boxes atomically. The source must hold
     * the amount; cross-currency boxes convert through the platform
     * rate (ExchangeRateSetting, read-only).
     */
    public function transfer(AccContext $ctx, array $data): AccCashTransfer
    {
        $key = $this->idempotencyKey($data);
        if ($key !== null) {
            $existing = AccCashTransfer::where('idempotency_key', $key)->first();
            if ($existing) {
                return $existing;
            }
        }

        $fromId = (int) ($data['from_box_id'] ?? 0);
        $toId = (int) ($data['to_box_id'] ?? 0);
        if ($fromId <= 0 || $toId <= 0 || $fromId === $toId) {
            throw new AccMoneyException('حدد صندوقين مختلفين للتحويل');
        }
        $amount = $this->positiveAmount($data['amount'] ?? null, 'مبلغ التحويل');

        $attempts = 0;
        do {
            try {
                return DB::transaction(function () use ($ctx, $data, $key, $fromId, $toId, $amount) {
                    // Lock both rows in id order to avoid deadlocks.
                    $boxes = AccCashBox::where('network_owner_id', $ctx->ownerId)
                        ->whereIn('id', [$fromId, $toId])
                        ->lockForUpdate()
                        ->get()
                        ->keyBy('id');
                    $from = $boxes->get($fromId);
                    $to = $boxes->get($toId);
                    if ($from === null || $to === null || ! $from->is_active || ! $to->is_active) {
                        throw new AccMoneyException('أحد الصندوقين غير موجود أو موقوف', 404);
                    }
                    if ((float) $from->balance < $amount - 0.005) {
                        throw new AccMoneyException(
                            "رصيد «{$from->name}» غير كافٍ — المتاح {$from->balance} والمطلوب {$amount}"
                        );
                    }

                    $toAmount = CurrencyService::convert($amount, $from->currency, $to->currency);
                    $base = $this->toBase($amount, $from->currency);

                    $transfer = AccCashTransfer::create([
                        'network_owner_id' => $ctx->ownerId,
                        'from_box_id' => $from->id,
                        'to_box_id' => $to->id,
                        'amount' => $amount,
                        'to_amount' => $toAmount,
                        'currency' => $from->currency,
                        'exchange_rate' => $this->rateToBase($from->currency),
                        'agent_id' => $ctx->agentId(),
                        'note' => $data['note'] ?? null,
                        'idempotency_key' => $key,
                    ]);

                    $entry = $this->posting->post('transfer', [
                        'network_owner_id' => $ctx->ownerId,
                        'agent_id' => $ctx->agentId(),
                        'doc_ref_id' => $transfer->id,
                        'memo' => "تحويل من «{$from->name}» إلى «{$to->name}»",
                        'idempotency_key' => 'transfer-' . $transfer->id,
                        'lines' => [
                            $this->leg(AccAccount::CASH_MAIN, 'box', $to->id, $base, 0),
                            $this->leg(AccAccount::CASH_MAIN, 'box', $from->id, 0, $base),
                        ],
                    ]);

                    $this->addToBox($from, -$amount);
                    $this->addToBox($to, $toAmount);
                    $transfer->journal_entry_id = $entry->id;
                    $transfer->save();

                    $this->audit($ctx, 'cashbox.transfer', 'acc_cash_transfers', $transfer->id, [
                        'from' => $from->id, 'to' => $to->id,
                        'amount' => $amount, 'to_amount' => $toAmount,
                    ]);

                    return $transfer;
                });
            } catch (QueryException $e) {
                if ($key !== null) {
                    $existing = AccCashTransfer::where('idempotency_key', $key)->first();
                    if ($existing) {
                        return $existing;
                    }
                }
                if (++$attempts >= 3 || ! $this->isUniqueViolation($e)) {
                    throw $e;
                }
            }
        } while (true);
    }

    // ── Expenses (money out) ─────────────────────────────────────

    /**
     * Post an expense against a cash box. Expenses may overdraw a
     * box (owner pays out-of-pocket — the drawer shows negative).
     */
    public function expense(AccContext $ctx, array $data): AccExpense
    {
        $key = $this->idempotencyKey($data);
        if ($key !== null) {
            $existing = AccExpense::where('idempotency_key', $key)->first();
            if ($existing) {
                return $existing;
            }
        }

        $amount = $this->positiveAmount($data['amount'] ?? null, 'مبلغ المصروف');
        $currency = $this->currency($data['currency'] ?? null);

        $attempts = 0;
        do {
            try {
                return DB::transaction(function () use ($ctx, $data, $key, $amount, $currency) {
                    AccExpenseCategory::ensureDefaultsFor($ctx->ownerId);
                    [$categoryId, $categoryName] = $this->resolveCategory($ctx, $data);

                    $box = $this->resolveBox($ctx, $data['cash_box_id'] ?? null, $currency);
                    $base = $this->toBase($amount, $currency);

                    $expense = AccExpense::create([
                        'network_owner_id' => $ctx->ownerId,
                        'category_id' => $categoryId,
                        'category_name' => $categoryName,
                        'amount' => $amount,
                        'currency' => $currency,
                        'exchange_rate' => $this->rateToBase($currency),
                        'base_amount' => $base,
                        'cash_box_id' => $box->id,
                        'agent_id' => $ctx->agentId(),
                        'incurred_at' => $this->timestamp($data['incurred_at'] ?? null),
                        'status' => AccExpense::STATUS_POSTED,
                        'note' => $data['note'] ?? null,
                        'idempotency_key' => $key,
                    ]);

                    $entry = $this->posting->post('expense', [
                        'network_owner_id' => $ctx->ownerId,
                        'agent_id' => $ctx->agentId(),
                        'doc_ref_id' => $expense->id,
                        'memo' => 'مصروف: ' . $categoryName,
                        'idempotency_key' => 'expense-' . $expense->id,
                        'lines' => [
                            $this->leg(AccAccount::EXPENSES, null, null, $base, 0),
                            $this->leg(AccAccount::CASH_MAIN, 'box', $box->id, 0, $base),
                        ],
                    ]);

                    $this->addToBox($box, -$this->toBoxAmount($amount, $currency, $box));
                    $expense->journal_entry_id = $entry->id;
                    $expense->save();

                    $this->audit($ctx, 'expense.create', 'acc_expenses', $expense->id, [
                        'category' => $categoryName,
                        'amount' => $amount,
                        'currency' => $currency,
                        'base' => $base,
                    ]);

                    return $expense;
                });
            } catch (QueryException $e) {
                if ($key !== null) {
                    $existing = AccExpense::where('idempotency_key', $key)->first();
                    if ($existing) {
                        return $existing;
                    }
                }
                if (++$attempts >= 3 || ! $this->isUniqueViolation($e)) {
                    throw $e;
                }
            }
        } while (true);
    }

    /** Cancel an expense with a reversal entry — never a delete. */
    public function voidExpense(AccContext $ctx, int $expenseId): AccExpense
    {
        return DB::transaction(function () use ($ctx, $expenseId) {
            $expense = AccExpense::where('network_owner_id', $ctx->ownerId)
                ->lockForUpdate()
                ->find($expenseId);
            if ($expense === null) {
                throw new AccMoneyException('المصروف غير موجود', 404);
            }
            if ($expense->status === AccExpense::STATUS_VOID) {
                return $expense; // replayable
            }

            $box = AccCashBox::where('network_owner_id', $ctx->ownerId)
                ->lockForUpdate()
                ->find($expense->cash_box_id);

            if ($expense->journal_entry_id !== null) {
                $entry = \App\Models\AccJournalEntry::find($expense->journal_entry_id);
                if ($entry !== null) {
                    $this->posting->reverse($entry, 'إلغاء مصروف #' . $expense->id);
                }
            }

            if ($box !== null) {
                $this->addToBox($box, $this->toBoxAmount(
                    (float) $expense->amount, $expense->currency, $box
                ));
            }

            $expense->status = AccExpense::STATUS_VOID;
            $expense->save();

            $this->audit($ctx, 'expense.void', 'acc_expenses', $expense->id, [
                'amount' => (float) $expense->amount,
            ]);

            return $expense;
        });
    }

    // ── Party + account resolution ───────────────────────────────

    /**
     * Validate the party and return
     * [collection_party_type, doc_party_id, account_code, party_name].
     * Named parties (customer/person/supplier-without-id) return a
     * null doc id — the caller stamps the row's own id afterwards.
     */
    private function resolveParty(
        AccContext $ctx,
        string $type,
        mixed $partyId,
        mixed $partyName,
        array $allowed
    ): array {
        if (! in_array($type, $allowed, true)) {
            throw new AccMoneyException('نوع الطرف غير معروف: ' . $type);
        }

        switch ($type) {
            case 'pos':
                $pos = AccPosPoint::where('network_owner_id', $ctx->ownerId)
                    ->find((int) $partyId);
                if ($pos === null) {
                    throw new AccMoneyException('نقطة البيع غير موجودة');
                }
                return ['pos', $pos->id, AccAccount::AR_POS, $pos->name];

            case 'distributor':
                $agent = AccAgent::where('network_owner_id', $ctx->ownerId)
                    ->where('role', 'distributor')
                    ->find((int) $partyId);
                if ($agent === null) {
                    throw new AccMoneyException('الموزع غير موجود');
                }
                return ['distributor', $agent->id, AccAccount::AR_DISTRIBUTORS, $agent->display_name];

            case 'supplier':
                $name = is_string($partyName) && $partyName !== '' ? $partyName : null;
                $id = null;
                if ($partyId !== null && $partyId !== '' && \Illuminate\Support\Facades\Schema::hasTable('acc_suppliers')) {
                    $supplier = DB::table('acc_suppliers')
                        ->where('network_owner_id', $ctx->ownerId)
                        ->find((int) $partyId);
                    if ($supplier !== null) {
                        $id = (int) $supplier->id;
                        $name = $name ?? $supplier->name;
                    }
                }
                if ($name === null) {
                    throw new AccMoneyException('اسم المورد مطلوب');
                }
                return ['supplier', $id, AccAccount::AP_SUPPLIERS, $name];

            default: // customer | person
                $name = is_string($partyName) && $partyName !== '' ? trim($partyName) : null;
                if ($name === null) {
                    throw new AccMoneyException('اسم الطرف مطلوب');
                }
                $id = $partyId !== null && $partyId !== '' ? (int) $partyId : null;
                return [$type, $id, AccAccount::CUSTOMER_BALANCES, $name];
        }
    }

    /** The (journal party_type, party_id) a debt posts against. */
    private function journalParty(AccDebt $debt): array
    {
        // 'person' isn't a journal party type — it books as a
        // named customer balance.
        $type = $debt->party_type === 'person' ? 'customer' : $debt->party_type;

        return [$type, (int) $debt->party_id];
    }

    private function receivableAccount(string $partyType): string
    {
        return match ($partyType) {
            'pos' => AccAccount::AR_POS,
            'distributor' => AccAccount::AR_DISTRIBUTORS,
            'supplier' => AccAccount::AP_SUPPLIERS,
            default => AccAccount::CUSTOMER_BALANCES,
        };
    }

    // ── Internals ────────────────────────────────────────────────

    private function leg(string $account, ?string $partyType, ?int $partyId, float $debit, float $credit): array
    {
        return [
            'account_code' => $account,
            'party_type' => $partyType,
            'party_id' => $partyId,
            'debit' => $debit,
            'credit' => $credit,
        ];
    }

    /**
     * The box to post against — the requested one, else the tenant's
     * lazily-created default (currency-matched when unspecified).
     */
    private function resolveBox(AccContext $ctx, mixed $boxId, string $currency): AccCashBox
    {
        if ($boxId !== null && $boxId !== '') {
            $box = AccCashBox::where('network_owner_id', $ctx->ownerId)
                ->where('is_active', true)
                ->lockForUpdate()
                ->find((int) $boxId);
            if ($box === null) {
                throw new AccMoneyException('الصندوق غير موجود أو موقوف');
            }

            return $box;
        }

        return AccCashBox::where('network_owner_id', $ctx->ownerId)
            ->where('is_default', true)
            ->where('is_active', true)
            ->lockForUpdate()
            ->first()
            ?? AccCashBox::ensureDefaultFor($ctx->ownerId, $currency);
    }

    private function resolveCategory(AccContext $ctx, array $data): array
    {
        $categoryId = isset($data['category_id']) && $data['category_id'] !== ''
            ? (int) $data['category_id'] : null;

        if ($categoryId !== null) {
            $cat = AccExpenseCategory::where('network_owner_id', $ctx->ownerId)
                ->where('is_active', true)
                ->find($categoryId);
            if ($cat === null) {
                throw new AccMoneyException('فئة المصروف غير موجودة');
            }

            return [$cat->id, $cat->name];
        }

        $name = isset($data['category_name']) && is_string($data['category_name'])
            ? trim($data['category_name']) : null;
        if ($name === null || $name === '') {
            throw new AccMoneyException('فئة المصروف مطلوبة');
        }

        return [null, $name];
    }

    private function addToBox(AccCashBox $box, float $delta): void
    {
        $box->balance = round((float) $box->balance + $delta, 2);
        $box->save();
    }

    /** Document amount → journal base (north) via the platform rate. */
    private function toBase(float $amount, string $currency): float
    {
        return CurrencyService::convert($amount, $currency, self::BASE_CURRENCY);
    }

    /** The rate that turns 1 unit of `$currency` into base units. */
    private function rateToBase(string $currency): float
    {
        if ($currency === self::BASE_CURRENCY) {
            return 1.0;
        }
        $mult = CurrencyService::multiplierNorthToSouth();

        return $currency === 'south' && $mult > 0 ? round(1 / $mult, 6) : 1.0;
    }

    /** Document amount expressed in the box's own currency. */
    private function toBoxAmount(float $amount, string $currency, AccCashBox $box): float
    {
        return CurrencyService::convert($amount, $currency, $box->currency);
    }

    private function currency(mixed $currency): string
    {
        $c = is_string($currency) && $currency !== '' ? strtolower($currency) : self::BASE_CURRENCY;
        if (! in_array($c, ['north', 'south'], true)) {
            throw new AccMoneyException('عملة غير مدعومة: ' . $c);
        }

        return $c;
    }

    private function positiveAmount(mixed $amount, string $label): float
    {
        $a = (float) $amount;
        if (! is_numeric($amount) || $a <= 0) {
            throw new AccMoneyException("{$label} يجب أن يكون أكبر من صفر");
        }

        return round($a, 2);
    }

    private function timestamp(mixed $value): Carbon
    {
        if ($value === null || $value === '') {
            return now();
        }
        if ($value instanceof \DateTimeInterface) {
            return Carbon::instance($value);
        }

        return Carbon::parse((string) $value);
    }

    private function idempotencyKey(array $data): ?string
    {
        $key = $data['idempotency_key'] ?? null;

        return is_string($key) && $key !== '' ? $key : null;
    }

    private function isUniqueViolation(QueryException $e): bool
    {
        $msg = $e->getMessage();

        return str_contains($msg, 'UNIQUE constraint failed')
            || str_contains($msg, 'Duplicate entry')
            || $e->getCode() === '23000';
    }

    private function audit(AccContext $ctx, string $action, string $entity, int $id, array $meta = []): void
    {
        AccAuditLog::create([
            'network_owner_id' => $ctx->ownerId,
            'agent_id' => $ctx->agentId(),
            'action' => $action,
            'entity' => $entity,
            'entity_id' => $id,
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }
}
