<?php

namespace App\Services;

use App\Models\AccAccount;
use App\Models\AccAuditLog;
use App\Models\AccBalance;
use App\Models\AccJournalEntry;
use App\Models\AccJournalLine;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The document-cycle heart of the accounting track (PLAN §3).
 *
 * Every financial event becomes ONE atomic transaction:
 *   acc_journal_entries + balanced acc_journal_lines
 *   + acc_balances updates (per party)
 *   + acc_audit_log row
 *
 * Rules enforced here:
 * - Σdebit = Σcredit per entry — unbalanced is rejected outright.
 * - idempotency_key makes every post replayable — a repeat call
 *   returns the original entry instead of duplicating it.
 * - Entries are immutable; corrections go through reverse().
 * - READ-ONLY access to platform tables: this service never writes
 *   to transactions/cards/wallet_logs (isolation contract §0.3).
 *
 * acc_sync_queue arrives with ACC-12 — the failure hook already
 * writes needs_review ops when the table exists.
 */
class AccPostingService
{
    /** Max tolerated rounding drift between debit/credit totals. */
    private const BALANCE_TOLERANCE = 0.005;

    /**
     * Post a balanced journal entry atomically.
     *
     * Payload:
     *   network_owner_id  int     required — tenant scope
     *   agent_id          int?    acting user (null = system)
     *   doc_ref_id        int?    source document id
     *   date              string|\DateTimeInterface?  default today
     *   currency          string  default 'YER'
     *   exchange_rate     float   default 1, must be > 0
     *   memo              string?
     *   idempotency_key   string? replay guard
     *   reversal_of_id    int?    set by reverse()
     *   lines             array   >= 2 legs, each:
     *       account_code  string  must exist in the owner's chart
     *       party_type    string? owner|pos|distributor|customer|supplier|box
     *       party_id      int?    required iff party_type set
     *       debit|credit  float   exactly one > 0 per line
     */
    public function post(string $docType, array $payload): AccJournalEntry
    {
        $ownerId = (int) ($payload['network_owner_id'] ?? 0);
        if ($ownerId <= 0) {
            throw new AccPostingException('network_owner_id مطلوب لعزل المستأجر');
        }
        if (! in_array($docType, AccJournalEntry::DOC_TYPES, true)) {
            throw new AccPostingException("نوع مستند غير معروف: {$docType}");
        }

        $lines = $this->validateLines($payload['lines'] ?? []);
        $key = isset($payload['idempotency_key']) && $payload['idempotency_key'] !== ''
            ? (string) $payload['idempotency_key'] : null;

        // Replayable: an earlier post with this key already succeeded.
        if ($key !== null) {
            $existing = AccJournalEntry::where('idempotency_key', $key)->first();
            if ($existing) {
                return $existing;
            }
        }

        $date = $this->resolveDate($payload['date'] ?? null);
        $exchangeRate = (float) ($payload['exchange_rate'] ?? 1);
        if ($exchangeRate <= 0) {
            throw new AccPostingException('سعر الصرف يجب أن يكون أكبر من صفر');
        }

        $started = microtime(true);
        $attempts = 0;

        do {
            try {
                return DB::transaction(function () use (
                    $docType, $payload, $ownerId, $lines, $key, $date, $exchangeRate, $started
                ) {
                    AccAccount::ensureDefaultsFor($ownerId);
                    $this->assertAccountsExist($ownerId, $lines);

                    $entry = AccJournalEntry::create([
                        'network_owner_id' => $ownerId,
                        'entry_no' => $this->nextEntryNo($ownerId, $date),
                        'doc_type' => $docType,
                        'doc_ref_id' => $payload['doc_ref_id'] ?? null,
                        'agent_id' => $payload['agent_id'] ?? null,
                        'date' => $date->toDateString(),
                        'currency' => $payload['currency'] ?? 'YER',
                        'exchange_rate' => $exchangeRate,
                        'memo' => $payload['memo'] ?? null,
                        'idempotency_key' => $key,
                        'reversal_of_id' => $payload['reversal_of_id'] ?? null,
                        'is_posted' => true,
                        'posted_at' => now(),
                    ]);

                    foreach ($lines as $line) {
                        $entry->lines()->create($line);
                        if ($line['party_type'] !== null) {
                            $this->applyBalance(
                                $ownerId,
                                $line['party_type'],
                                (int) $line['party_id'],
                                $line['debit'] - $line['credit']
                            );
                        }
                    }

                    $this->writeAudit($ownerId, $payload['agent_id'] ?? null, $entry, $lines, $payload, $started);

                    return $entry;
                });
            } catch (QueryException $e) {
                // A racing request may have inserted the same
                // idempotency key — treat as a normal replay.
                if ($key !== null) {
                    $existing = AccJournalEntry::where('idempotency_key', $key)->first();
                    if ($existing) {
                        return $existing;
                    }
                }
                // Retry entry-number races on the unique index.
                if (++$attempts >= 3 || ! $this->isUniqueViolation($e)) {
                    $this->queueFailedOp($docType, $payload, $e);
                    throw $e;
                }
            } catch (\Throwable $e) {
                $this->queueFailedOp($docType, $payload, $e);
                throw $e;
            }
        } while (true);
    }

    /**
     * Correct a posted entry with an exact inverse entry (PLAN §3).
     * Idempotent: reversing the same entry twice returns the first
     * reversal instead of compounding.
     */
    public function reverse(AccJournalEntry $entry, ?string $memo = null): AccJournalEntry
    {
        $lines = $entry->lines()->get()->map(fn (AccJournalLine $l) => [
            'account_code' => $l->account_code,
            'party_type' => $l->party_type,
            'party_id' => $l->party_id,
            'debit' => (float) $l->credit,
            'credit' => (float) $l->debit,
        ])->all();

        return $this->post($entry->doc_type, [
            'network_owner_id' => $entry->network_owner_id,
            'agent_id' => $entry->agent_id,
            'doc_ref_id' => $entry->doc_ref_id,
            'memo' => $memo ?? ('قيد عكسي لـ ' . $entry->entry_no),
            'currency' => $entry->currency,
            'exchange_rate' => (float) $entry->exchange_rate,
            'idempotency_key' => 'rev-' . $entry->id,
            'reversal_of_id' => $entry->id,
            'lines' => $lines,
        ]);
    }

    /** Current running balance of a party (0 when never posted to). */
    public function balanceOf(int $ownerId, string $partyType, int $partyId): float
    {
        $row = AccBalance::where('network_owner_id', $ownerId)
            ->where('party_type', $partyType)
            ->where('party_id', $partyId)
            ->first();

        return (float) ($row->balance ?? 0);
    }

    // ── Internals ────────────────────────────────────────────────

    private function validateLines(mixed $lines): array
    {
        if (! is_array($lines) || count($lines) < 2) {
            throw new AccPostingException('قيد اليومية يتطلب سطرين على الأقل');
        }

        $clean = [];
        $totalDebit = 0.0;
        $totalCredit = 0.0;

        foreach ($lines as $i => $line) {
            $debit = (float) ($line['debit'] ?? 0);
            $credit = (float) ($line['credit'] ?? 0);
            $code = trim((string) ($line['account_code'] ?? ''));

            if ($code === '') {
                throw new AccPostingException("السطر {$i}: account_code مطلوب");
            }
            if ($debit < 0 || $credit < 0) {
                throw new AccPostingException("السطر {$i}: مبالغ سالبة مرفوضة");
            }
            if ($debit > 0 && $credit > 0) {
                throw new AccPostingException("السطر {$i}: لا يجمع مديناً ودائناً معاً");
            }
            if ($debit == 0.0 && $credit == 0.0) {
                throw new AccPostingException("السطر {$i}: سطر صفري مرفوض");
            }

            $partyType = $line['party_type'] ?? null;
            $partyId = $line['party_id'] ?? null;
            if (($partyType === null) !== ($partyId === null)) {
                throw new AccPostingException("السطر {$i}: party_type و party_id يأتيان معاً");
            }
            if ($partyType !== null && ! in_array($partyType, AccJournalLine::PARTY_TYPES, true)) {
                throw new AccPostingException("السطر {$i}: نوع طرف غير معروف: {$partyType}");
            }

            $totalDebit += $debit;
            $totalCredit += $credit;
            $clean[] = [
                'account_code' => $code,
                'party_type' => $partyType,
                'party_id' => $partyId !== null ? (int) $partyId : null,
                'debit' => $debit,
                'credit' => $credit,
            ];
        }

        if (abs($totalDebit - $totalCredit) > self::BALANCE_TOLERANCE) {
            throw new AccPostingException(
                "القيد غير متوازن — مدين {$totalDebit} ≠ دائن {$totalCredit}"
            );
        }

        return $clean;
    }

    private function assertAccountsExist(int $ownerId, array $lines): void
    {
        $codes = array_values(array_unique(array_column($lines, 'account_code')));
        $found = AccAccount::where('network_owner_id', $ownerId)
            ->whereIn('code', $codes)
            ->where('is_active', true)
            ->pluck('code')
            ->all();

        $missing = array_diff($codes, $found);
        if ($missing !== []) {
            throw new AccPostingException(
                'حسابات غير موجودة في الدليل: ' . implode(', ', $missing)
            );
        }
    }

    private function applyBalance(int $ownerId, string $partyType, int $partyId, float $delta): void
    {
        $balance = AccBalance::where('network_owner_id', $ownerId)
            ->where('party_type', $partyType)
            ->where('party_id', $partyId)
            ->lockForUpdate()
            ->first()
            ?? new AccBalance([
                'network_owner_id' => $ownerId,
                'party_type' => $partyType,
                'party_id' => $partyId,
                'balance' => 0,
            ]);

        $balance->balance = (float) $balance->balance + $delta;
        $balance->save();
    }

    private function nextEntryNo(int $ownerId, Carbon $date): string
    {
        $prefix = 'JE-' . $date->format('Ymd') . '-';
        $last = AccJournalEntry::where('network_owner_id', $ownerId)
            ->where('entry_no', 'like', $prefix . '%')
            ->lockForUpdate()
            ->max('entry_no');

        $seq = $last === null ? 1 : ((int) substr($last, -5)) + 1;

        return $prefix . str_pad((string) $seq, 5, '0', STR_PAD_LEFT);
    }

    private function writeAudit(
        int $ownerId,
        ?int $agentId,
        AccJournalEntry $entry,
        array $lines,
        array $payload,
        float $started
    ): void {
        AccAuditLog::create([
            'network_owner_id' => $ownerId,
            'agent_id' => $agentId,
            'action' => 'journal.post',
            'entity' => 'acc_journal_entries',
            'entity_id' => $entry->id,
            'meta' => [
                'doc_type' => $entry->doc_type,
                'doc_ref_id' => $entry->doc_ref_id,
                'entry_no' => $entry->entry_no,
                'lines_count' => count($lines),
                'total' => array_sum(array_column($lines, 'debit')),
                'latency_ms' => round((microtime(true) - $started) * 1000, 2),
                'payload_hash' => substr(sha1(json_encode($payload) ?: ''), 0, 16),
            ],
            'created_at' => now(),
        ]);
    }

    private function resolveDate(mixed $date): Carbon
    {
        if ($date === null) {
            return Carbon::today();
        }
        if ($date instanceof \DateTimeInterface) {
            return Carbon::instance($date);
        }

        return Carbon::parse((string) $date);
    }

    private function isUniqueViolation(QueryException $e): bool
    {
        $msg = $e->getMessage();

        return str_contains($msg, 'UNIQUE constraint failed')
            || str_contains($msg, 'Duplicate entry')
            || $e->getCode() === '23000';
    }

    /**
     * Forward-compatible with ACC-12's acc_sync_queue — writes a
     * needs_review op when the table exists, silently no-ops before.
     */
    private function queueFailedOp(string $docType, array $payload, \Throwable $e): void
    {
        try {
            if (! Schema::hasTable('acc_sync_queue')) {
                return;
            }
            DB::table('acc_sync_queue')->insert([
                'op_type' => 'post:' . $docType,
                'payload' => json_encode(
                    ['doc' => $payload, 'error' => $e->getMessage()],
                    JSON_UNESCAPED_UNICODE
                ),
                'status' => 'needs_review',
                'created_at' => now(),
            ]);
        } catch (\Throwable) {
            // The queue must never break posting error handling.
        }
    }
}
