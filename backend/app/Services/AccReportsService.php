<?php

namespace App\Services;

use App\Models\AccAccount;
use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\AccCollection;
use App\Models\AccCommission;
use App\Models\AccDebt;
use App\Models\AccExpense;
use App\Models\AccJournalEntry;
use App\Models\AccPosPoint;
use App\Models\AccSale;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-09 — the read-only reporting layer (PLAN §4 + §5).
 *
 * Nothing here writes: every figure is either aggregated straight
 * from acc_journal_lines (the document-cycle source of truth, so
 * reports can never disagree with posted entries) or from the
 * document tables (acc_sales/acc_collections/…) for operational
 * counts. Every aggregate is tenant-scoped on network_owner_id.
 *
 * Endpoints it feeds:
 *   /summary · /dashboard/trend · /reports/sales
 *   /reports/pos-performance · /reports/distributor-commissions
 *   /reports/collections-daily · /audit-log · /journal(/id)
 */
class AccReportsService
{
    /** doc_types that represent revenue-producing sales activity. */
    private const SALE_DOCS = ['sale', 'pos_sale', 'card_purchase_platform'];

    // ── Executive summary ──────────────────────────────────────

    /**
     * Headline figures for the manager home. Money figures come
     * from journal legs — this is what guarantees «report = قيود».
     */
    public function summary(AccContext $ctx): array
    {
        $owner = $ctx->ownerId;
        $today = Carbon::today();
        $monthStart = $today->copy()->startOfMonth();

        $month = $this->accountAgg($owner, $monthStart, $today->copy()->endOfDay());
        $day = $this->accountAgg($owner, $today->copy()->startOfDay(), $today->copy()->endOfDay());

        $revenue = $this->netCredit($month, AccAccount::REVENUE_SALES)
            + $this->netCredit($month, AccAccount::REVENUE_COMMISSIONS);
        $expenses = $this->netDebit($month, AccAccount::EXPENSES);

        return [
            'generated_at' => now()->toISOString(),
            'today' => [
                'date' => $today->toDateString(),
                'sales' => round(
                    $this->netCredit($day, AccAccount::REVENUE_SALES)
                    + $this->netCredit($day, AccAccount::REVENUE_COMMISSIONS), 2),
                'collections' => round($this->docLegSum(
                    $owner, 'collection', AccAccount::CASH_MAIN, 'debit',
                    $today->copy()->startOfDay(), $today->copy()->endOfDay()
                ), 2),
                'expenses' => round($this->docLegSum(
                    $owner, 'expense', AccAccount::EXPENSES, 'debit',
                    $today->copy()->startOfDay(), $today->copy()->endOfDay()
                ), 2),
                'sales_docs' => $this->salesDocsCount($owner, $today, $today),
            ],
            'month' => [
                'from' => $monthStart->toDateString(),
                'to' => $today->toDateString(),
                'revenue' => round($revenue, 2),
                'expenses' => round($expenses, 2),
                'operating_result' => round($revenue - $expenses, 2),
                'entries' => $this->entriesCount($owner, $monthStart, $today->copy()->endOfDay()),
            ],
            'cash' => $this->cashBlock($owner),
            'parties' => $this->partyBalances($owner),
            'stock' => $this->stockBlock($owner),
            'debts' => $this->debtsBlock($owner),
        ];
    }

    // ── 30-day trend ───────────────────────────────────────────

    /**
     * Per-day series for the trend chart. Three journal-derived
     * streams: sales revenue (credits on 4xxx across sale docs),
     * collections (box debits on collection docs), and expenses
     * (expense-account debits on expense/damaged docs).
     */
    public function trend(AccContext $ctx, int $days = 30): array
    {
        $days = max(1, min(365, $days));
        $owner = $ctx->ownerId;
        $to = Carbon::today();
        $from = $to->copy()->subDays($days - 1);

        $revenue = $this->dailyAccountFlow($owner, [AccAccount::REVENUE_SALES, AccAccount::REVENUE_COMMISSIONS], null, $from, $to);
        $collections = $this->dailyAccountFlow($owner, [AccAccount::CASH_MAIN], 'collection', $from, $to, 'debit');
        $expenses = $this->dailyAccountFlow($owner, [AccAccount::EXPENSES], ['expense', 'damaged'], $from, $to, 'debit');

        $series = [];
        for ($d = $from->copy(); $d->lte($to); $d->addDay()) {
            $key = $d->toDateString();
            $series[] = [
                'date' => $key,
                'sales' => round((float) ($revenue[$key] ?? 0), 2),
                'collections' => round((float) ($collections[$key] ?? 0), 2),
                'expenses' => round((float) ($expenses[$key] ?? 0), 2),
            ];
        }

        return [
            'days' => $days,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'points' => $series,
        ];
    }

    // ── Sales report ───────────────────────────────────────────

    /**
     * The sales book over a period: operational rollups from
     * acc_sales (+items) PLUS a journal reconciliation block so the
     * screen can show the figures tie out against posted entries.
     */
    public function salesReport(AccContext $ctx, ?string $from, ?string $to): array
    {
        [$fromDate, $toDate] = $this->period($from, $to);
        $owner = $ctx->ownerId;

        $sales = AccSale::where('network_owner_id', $owner)
            ->where('status', AccSale::STATUS_POSTED)
            ->whereBetween('sold_at', [$fromDate, $toDate])
            ->get();

        $saleIds = $sales->pluck('id');
        $byCategory = $saleIds->isEmpty()
            ? collect()
            : DB::table('acc_sale_items')
                ->whereIn('sale_id', $saleIds)
                ->selectRaw('category_id, category_name, SUM(qty) as qty, SUM(line_total) as amount')
                ->groupBy('category_id', 'category_name')
                ->orderByDesc('amount')
                ->get();

        $posNames = AccPosPoint::where('network_owner_id', $owner)->pluck('name', 'id');
        $agentNames = AccAgent::where('network_owner_id', $owner)->pluck('display_name', 'id');

        $byPos = $sales->groupBy('pos_id')
            ->map(fn ($rows, $id) => [
                'pos_id' => (int) $id,
                'pos_name' => $posNames[$id] ?? ('#' . $id),
                'count' => $rows->count(),
                'total' => round((float) $rows->sum('base_total'), 2),
            ])->sortByDesc('total')->values();

        $byDistributor = $sales->groupBy(fn (AccSale $s) => $s->distributor_id ?? 0)
            ->map(fn ($rows, $id) => [
                'distributor_id' => $id ? (int) $id : null,
                'distributor_name' => $id
                    ? ($agentNames[$id] ?? ('#' . $id))
                    : 'بيع مباشر (المالك/الإدارة)',
                'count' => $rows->count(),
                'total' => round((float) $rows->sum('base_total'), 2),
                'commission' => round((float) $rows->sum('commission_amount'), 2),
            ])->sortByDesc('total')->values();

        $byKind = $sales->groupBy('payment_kind')
            ->map(fn ($rows, $kind) => [
                'kind' => $kind,
                'count' => $rows->count(),
                'total' => round((float) $rows->sum('base_total'), 2),
            ])->values();

        $daily = $sales->groupBy(fn (AccSale $s) => $s->sold_at->toDateString())
            ->map(fn ($rows, $date) => [
                'date' => $date,
                'count' => $rows->count(),
                'total' => round((float) $rows->sum('base_total'), 2),
            ])->sortKeys()->values();

        // Journal side — revenue credited by doc_type for the same
        // window. acc_sales only tracks distributor/POS sales, so
        // bundle orders and platform card sales show here too.
        $journalRevenue = $this->revenueByDocType($owner, $fromDate, $toDate);

        return [
            'from' => $fromDate->toDateString(),
            'to' => $toDate->toDateString(),
            'totals' => [
                'count' => $sales->count(),
                'total' => round((float) $sales->sum('base_total'), 2),
                'paid' => round((float) $sales->sum('base_paid'), 2),
                'credit' => round(
                    (float) $sales->sum('base_total') - (float) $sales->sum('base_paid'), 2),
                'commission' => round((float) $sales->sum('commission_amount'), 2),
            ],
            'journal' => [
                'revenue_by_doc' => $journalRevenue,
                'revenue_total' => round(array_sum(array_column($journalRevenue, 'amount')), 2),
            ],
            'by_kind' => $byKind,
            'by_category' => $byCategory->map(fn ($r) => [
                'category_id' => $r->category_id !== null ? (int) $r->category_id : null,
                'category_name' => $r->category_name,
                'qty' => (float) $r->qty,
                'amount' => (float) $r->amount,
            ])->values(),
            'by_pos' => $byPos,
            'by_distributor' => $byDistributor,
            'daily' => $daily,
        ];
    }

    // ── POS strength analysis ──────────────────────────────────

    /**
     * Per-point strength card: period sales + collections, live AR
     * (acc_balances), points/profit balances, order pipeline, last
     * activity — scored 0..100 against the busiest point and tiered
     * strong|medium|active|dormant.
     */
    public function posPerformance(AccContext $ctx, int $days = 30): array
    {
        $days = max(1, min(365, $days));
        $owner = $ctx->ownerId;
        $to = Carbon::today()->endOfDay();
        $from = Carbon::today()->subDays($days - 1)->startOfDay();

        $points = AccPosPoint::where('network_owner_id', $owner)->orderBy('name')->get();
        if ($points->isEmpty()) {
            return ['days' => $days, 'from' => $from->toDateString(),
                'to' => $to->toDateString(), 'points' => []];
        }

        $sales = AccSale::where('network_owner_id', $owner)
            ->where('status', AccSale::STATUS_POSTED)
            ->whereBetween('sold_at', [$from, $to])
            ->selectRaw('pos_id, COUNT(*) as cnt, SUM(base_total) as total, MAX(sold_at) as last_at')
            ->groupBy('pos_id')->get()->keyBy('pos_id');

        $collections = AccCollection::where('network_owner_id', $owner)
            ->where('party_type', 'pos')
            ->whereBetween('collected_at', [$from, $to])
            ->selectRaw('party_id, COUNT(*) as cnt, SUM(base_amount) as total')
            ->groupBy('party_id')->get()->keyBy('party_id');

        $orders = Schema::hasTable('acc_pos_orders')
            ? DB::table('acc_pos_orders')
                ->where('network_owner_id', $owner)
                ->whereBetween('created_at', [$from, $to])
                ->selectRaw("pos_id,
                    SUM(CASE WHEN status='approved' THEN 1 ELSE 0 END) as approved,
                    SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) as pending")
                ->groupBy('pos_id')->get()->keyBy('pos_id')
            : collect();

        $ar = DB::table('acc_balances')
            ->where('network_owner_id', $owner)
            ->where('party_type', 'pos')
            ->pluck('balance', 'party_id');

        $rows = $points->map(function (AccPosPoint $p) use ($sales, $collections, $orders, $ar) {
            $s = $sales->get($p->id);
            $c = $collections->get($p->id);
            $o = $orders->get($p->id);
            $salesTotal = round((float) ($s->total ?? 0), 2);
            $collectionsTotal = round((float) ($c->total ?? 0), 2);

            return [
                'pos_id' => $p->id,
                'name' => $p->name,
                'status' => $p->status,
                'location' => $p->location,
                'sales_count' => (int) ($s->cnt ?? 0),
                'sales_total' => $salesTotal,
                'collections_total' => $collectionsTotal,
                'ar_balance' => round((float) ($ar[$p->id] ?? 0), 2),
                'points_balance' => (float) $p->points_balance,
                'profit_balance' => (float) $p->profit_balance,
                'credit_limit' => (float) $p->credit_limit,
                'orders_approved' => (int) ($o->approved ?? 0),
                'orders_pending' => (int) ($o->pending ?? 0),
                'last_sale_at' => $s->last_at ?? null,
                '_activity' => $salesTotal + $collectionsTotal,
            ];
        });

        $maxActivity = max(1.0, (float) $rows->max('_activity'));
        $points = $rows->map(function (array $r) use ($maxActivity) {
            $score = (int) round(100 * $r['_activity'] / $maxActivity);
            $r['score'] = $score;
            $r['tier'] = $r['_activity'] <= 0
                ? 'dormant'
                : ($score >= 75 ? 'strong' : ($score >= 35 ? 'medium' : 'active'));
            unset($r['_activity']);

            return $r;
        })->sortByDesc('score')->values();

        return [
            'days' => $days,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'points' => $points,
        ];
    }

    // ── Distributor commissions ────────────────────────────────

    /**
     * acc_commissions rows (period filter optional) plus a journal
     * reconciliation: what the POS_PROFITS liability legs credited
     * each distributor inside the period — the two must agree.
     */
    public function commissionsReport(AccContext $ctx, ?string $period = null): array
    {
        $owner = $ctx->ownerId;

        $query = AccCommission::where('network_owner_id', $owner)->orderByDesc('period');
        if ($period !== null && preg_match('/^\d{4}-\d{2}$/', $period)) {
            $query->where('period', $period);
        }
        $rows = $query->get();

        $agentNames = AccAgent::where('network_owner_id', $owner)->pluck('display_name', 'id');

        // Journal check: net credit on the POS_PROFITS liability
        // per distributor — accruals credit, payouts debit — so the
        // figure equals (accrued − paid) for the filtered window.
        $journalNet = DB::table('acc_journal_lines')
            ->join('acc_journal_entries', 'acc_journal_lines.entry_id', '=', 'acc_journal_entries.id')
            ->where('acc_journal_entries.network_owner_id', $owner)
            ->where('acc_journal_entries.is_posted', true)
            ->where('acc_journal_lines.account_code', AccAccount::POS_PROFITS)
            ->where('acc_journal_lines.party_type', 'distributor')
            ->selectRaw('acc_journal_lines.party_id,
                SUM(acc_journal_lines.credit - acc_journal_lines.debit) as net')
            ->groupBy('acc_journal_lines.party_id')
            ->pluck('net', 'party_id');

        $byDistributor = $rows->groupBy('distributor_id')
            ->map(fn ($r, $id) => [
                'distributor_id' => (int) $id,
                'distributor_name' => $agentNames[$id] ?? ('#' . $id),
                'sales_amount' => round((float) $r->sum('sales_amount'), 2),
                'commission_amount' => round((float) $r->sum('commission_amount'), 2),
                'journal_net' => round((float) ($journalNet[$id] ?? 0), 2),
            ])->sortByDesc('commission_amount')->values();

        return [
            'period' => $period,
            'totals' => [
                'sales_amount' => round((float) $rows->sum('sales_amount'), 2),
                'commission_amount' => round((float) $rows->sum('commission_amount'), 2),
                'accrued' => round((float) $rows->where('status', AccCommission::STATUS_ACCRUED)->sum('commission_amount'), 2),
                'paid' => round((float) $rows->where('status', AccCommission::STATUS_PAID)->sum('commission_amount'), 2),
            ],
            'by_distributor' => $byDistributor,
            'rows' => $rows->map(fn (AccCommission $c) => [
                'id' => $c->id,
                'distributor_id' => $c->distributor_id,
                'distributor_name' => $agentNames[$c->distributor_id] ?? null,
                'period' => $c->period,
                'sales_amount' => (float) $c->sales_amount,
                'commission_amount' => (float) $c->commission_amount,
                'status' => $c->status,
                'paid_at' => $c->paid_at?->toISOString(),
            ])->values(),
        ];
    }

    // ── Daily collections statement (PDF source) ───────────────

    /**
     * One day's collection register — the data behind the كشف
     * تحصيل يومي PDF. Totals split by currency and box, and the
     * journal check (box debit legs on collection docs) rides
     * alongside so the printed figure can be tied to the books.
     */
    public function collectionsDaily(AccContext $ctx, ?string $date = null): array
    {
        $owner = $ctx->ownerId;
        $day = $date ? Carbon::parse($date) : Carbon::today();

        $rows = AccCollection::with(['box:id,name', 'collector:id,display_name'])
            ->where('network_owner_id', $owner)
            ->whereDate('collected_at', $day)
            ->orderBy('collected_at')
            ->get();

        $byCurrency = $rows->groupBy('currency')
            ->map(fn ($r, $cur) => ['currency' => $cur,
                'count' => $r->count(), 'total' => round((float) $r->sum('amount'), 2)])
            ->values();
        $byBox = $rows->groupBy('cash_box_id')
            ->map(fn ($r, $id) => [
                'box_id' => (int) $id,
                'box_name' => $r->first()->box?->name ?? 'الرئيسي',
                'currency' => $r->first()->currency,
                'count' => $r->count(),
                'total' => round((float) $r->sum('amount'), 2),
            ])->values();

        return [
            'date' => $day->toDateString(),
            'totals' => [
                'count' => $rows->count(),
                'total_base' => round((float) $rows->sum('base_amount'), 2),
                'journal_base' => round($this->docLegSum(
                    $owner, 'collection', AccAccount::CASH_MAIN, 'debit',
                    $day->copy()->startOfDay(), $day->copy()->endOfDay()
                ), 2),
            ],
            'by_currency' => $byCurrency,
            'by_box' => $byBox,
            'rows' => $rows->map(fn (AccCollection $c) => [
                'id' => $c->id,
                'party_type' => $c->party_type,
                'party_name' => $c->party_name,
                'phone' => $c->phone,
                'amount' => (float) $c->amount,
                'currency' => $c->currency,
                'base_amount' => (float) $c->base_amount,
                'box_name' => $c->box?->name,
                'collector' => $c->collector?->display_name,
                'debt_id' => $c->debt_id,
                'collected_at' => $c->collected_at?->toISOString(),
                'note' => $c->note,
            ])->values(),
        ];
    }

    // ── Audit trail ────────────────────────────────────────────

    /** Paginated audit log with agent names + optional filters. */
    public function auditLog(AccContext $ctx, array $filters)
    {
        $query = AccAuditLog::where('network_owner_id', $ctx->ownerId)
            ->latest('created_at')->latest('id');

        if (! empty($filters['action'])) {
            $query->where('action', 'like', '%' . $filters['action'] . '%');
        }
        if (! empty($filters['entity'])) {
            $query->where('entity', $filters['entity']);
        }
        if (! empty($filters['agent_id'])) {
            $query->where('agent_id', (int) $filters['agent_id']);
        }
        if (! empty($filters['from'])) {
            $query->where('created_at', '>=', Carbon::parse($filters['from'])->startOfDay());
        }
        if (! empty($filters['to'])) {
            $query->where('created_at', '<=', Carbon::parse($filters['to'])->endOfDay());
        }

        $agentNames = AccAgent::where('network_owner_id', $ctx->ownerId)
            ->pluck('display_name', 'id');

        return $query->paginate(30)->through(fn (AccAuditLog $l) => [
            'id' => $l->id,
            'action' => $l->action,
            'entity' => $l->entity,
            'entity_id' => $l->entity_id,
            'agent_id' => $l->agent_id,
            'agent_name' => $l->agent_id !== null
                ? ($agentNames[$l->agent_id] ?? ('#' . $l->agent_id))
                : 'النظام',
            'meta' => $l->meta,
            'created_at' => $l->created_at?->toISOString(),
        ]);
    }

    // ── Journal browser ────────────────────────────────────────

    /** Paginated journal entries + balance totals for the filter. */
    public function journal(AccContext $ctx, array $filters)
    {
        $owner = $ctx->ownerId;
        $query = AccJournalEntry::where('network_owner_id', $owner)
            ->latest('acc_journal_entries.date')->latest('acc_journal_entries.id');

        if (! empty($filters['doc_type'])) {
            $query->where('doc_type', $filters['doc_type']);
        }
        if (! empty($filters['from'])) {
            $query->whereDate('date', '>=', $filters['from']);
        }
        if (! empty($filters['to'])) {
            $query->whereDate('date', '<=', $filters['to']);
        }

        $totals = (clone $query)
            ->join('acc_journal_lines', 'acc_journal_entries.id', '=', 'acc_journal_lines.entry_id')
            ->selectRaw('SUM(acc_journal_lines.debit) as d, SUM(acc_journal_lines.credit) as c')
            ->first();

        $page = $query->paginate(25);

        return [
            'totals' => [
                'debit' => round((float) ($totals->d ?? 0), 2),
                'credit' => round((float) ($totals->c ?? 0), 2),
            ],
            'entries' => $page->through(fn (AccJournalEntry $e) => [
                'id' => $e->id,
                'entry_no' => $e->entry_no,
                'doc_type' => $e->doc_type,
                'doc_ref_id' => $e->doc_ref_id,
                'date' => $e->date?->toDateString(),
                'memo' => $e->memo,
                'is_posted' => (bool) $e->is_posted,
                'reversal_of_id' => $e->reversal_of_id,
            ]),
        ];
    }

    /** One entry with its legs resolved to account/party names. */
    public function journalEntry(AccContext $ctx, int $id): ?array
    {
        $entry = AccJournalEntry::with('lines')
            ->where('network_owner_id', $ctx->ownerId)
            ->find($id);
        if ($entry === null) {
            return null;
        }

        $accounts = AccAccount::where('network_owner_id', $ctx->ownerId)
            ->pluck('name', 'code');
        $agents = AccAgent::where('network_owner_id', $ctx->ownerId)
            ->pluck('display_name', 'id');
        $posNames = AccPosPoint::where('network_owner_id', $ctx->ownerId)
            ->pluck('name', 'id');
        $boxNames = DB::table('acc_cash_boxes')
            ->where('network_owner_id', $ctx->ownerId)
            ->pluck('name', 'id');

        return [
            'id' => $entry->id,
            'entry_no' => $entry->entry_no,
            'doc_type' => $entry->doc_type,
            'doc_ref_id' => $entry->doc_ref_id,
            'agent' => $entry->agent_id !== null
                ? ($agents[$entry->agent_id] ?? ('#' . $entry->agent_id))
                : 'النظام',
            'date' => $entry->date?->toDateString(),
            'currency' => $entry->currency,
            'exchange_rate' => (float) $entry->exchange_rate,
            'memo' => $entry->memo,
            'reversal_of_id' => $entry->reversal_of_id,
            'posted_at' => $entry->posted_at?->toISOString(),
            'lines' => $entry->lines->map(fn ($l) => [
                'account_code' => $l->account_code,
                'account_name' => $accounts[$l->account_code] ?? $l->account_code,
                'party_type' => $l->party_type,
                'party_id' => $l->party_id,
                'party_name' => match ($l->party_type) {
                    'pos' => $posNames[$l->party_id] ?? null,
                    'distributor' => $agents[$l->party_id] ?? null,
                    'box' => $boxNames[$l->party_id] ?? null,
                    default => null,
                },
                'debit' => (float) $l->debit,
                'credit' => (float) $l->credit,
            ])->values(),
        ];
    }

    // ── Internals ──────────────────────────────────────────────

    /** Per-account debit/credit sums over a period (posted only). */
    private function accountAgg(int $owner, Carbon $from, Carbon $to): array
    {
        return DB::table('acc_journal_lines')
            ->join('acc_journal_entries', 'acc_journal_lines.entry_id', '=', 'acc_journal_entries.id')
            ->where('acc_journal_entries.network_owner_id', $owner)
            ->where('acc_journal_entries.is_posted', true)
            ->whereDate('acc_journal_entries.date', '>=', $from)
            ->whereDate('acc_journal_entries.date', '<=', $to)
            ->selectRaw('acc_journal_lines.account_code as code,
                SUM(acc_journal_lines.debit) as d, SUM(acc_journal_lines.credit) as c')
            ->groupBy('acc_journal_lines.account_code')
            ->get()
            ->keyBy('code')
            ->all();
    }

    private function netCredit(array $agg, string $code): float
    {
        $row = $agg[$code] ?? null;

        return $row === null ? 0.0 : ((float) $row->c - (float) $row->d);
    }

    private function netDebit(array $agg, string $code): float
    {
        $row = $agg[$code] ?? null;

        return $row === null ? 0.0 : ((float) $row->d - (float) $row->c);
    }

    /**
     * Sum one side of an account's legs for a single doc_type in a
     * datetime window — e.g. box debits on collection docs = money in.
     */
    private function docLegSum(
        int $owner, string $docType, string $account, string $side, Carbon $from, Carbon $to
    ): float {
        return (float) DB::table('acc_journal_lines')
            ->join('acc_journal_entries', 'acc_journal_lines.entry_id', '=', 'acc_journal_entries.id')
            ->where('acc_journal_entries.network_owner_id', $owner)
            ->where('acc_journal_entries.is_posted', true)
            ->where('acc_journal_entries.doc_type', $docType)
            ->where('acc_journal_lines.account_code', $account)
            ->whereDate('acc_journal_entries.date', '>=', $from)
            ->whereDate('acc_journal_entries.date', '<=', $to)
            ->sum('acc_journal_lines.' . $side);
    }

    /**
     * Daily net flow for a set of accounts. `$docTypes` null = all
     * docs; 'debit'|'credit' picks the leading side (net otherwise).
     */
    private function dailyAccountFlow(
        int $owner, array $accounts, string|array|null $docTypes, Carbon $from, Carbon $to,
        ?string $side = null
    ): array {
        $q = DB::table('acc_journal_lines')
            ->join('acc_journal_entries', 'acc_journal_lines.entry_id', '=', 'acc_journal_entries.id')
            ->where('acc_journal_entries.network_owner_id', $owner)
            ->where('acc_journal_entries.is_posted', true)
            ->whereIn('acc_journal_lines.account_code', $accounts)
            ->whereDate('acc_journal_entries.date', '>=', $from)
            ->whereDate('acc_journal_entries.date', '<=', $to);

        if ($docTypes !== null) {
            $q->whereIn('acc_journal_entries.doc_type', (array) $docTypes);
        }

        $expr = match ($side) {
            'debit' => 'SUM(acc_journal_lines.debit)',
            'credit' => 'SUM(acc_journal_lines.credit)',
            default => 'SUM(acc_journal_lines.credit - acc_journal_lines.debit)',
        };

        return $q->selectRaw("DATE(acc_journal_entries.date) as d, {$expr} as v")
            ->groupBy(DB::raw('DATE(acc_journal_entries.date)'))
            ->pluck('v', 'd')
            ->all();
    }

    /** Revenue credited per doc_type over a period. */
    private function revenueByDocType(int $owner, Carbon $from, Carbon $to): array
    {
        return DB::table('acc_journal_lines')
            ->join('acc_journal_entries', 'acc_journal_lines.entry_id', '=', 'acc_journal_entries.id')
            ->where('acc_journal_entries.network_owner_id', $owner)
            ->where('acc_journal_entries.is_posted', true)
            ->whereIn('acc_journal_lines.account_code', [AccAccount::REVENUE_SALES, AccAccount::REVENUE_COMMISSIONS])
            ->whereDate('acc_journal_entries.date', '>=', $from)
            ->whereDate('acc_journal_entries.date', '<=', $to)
            ->selectRaw('acc_journal_entries.doc_type as doc,
                SUM(acc_journal_lines.credit - acc_journal_lines.debit) as amount')
            ->groupBy('acc_journal_entries.doc_type')
            ->get()
            ->map(fn ($r) => ['doc_type' => $r->doc, 'amount' => round((float) $r->amount, 2)])
            ->values()
            ->all();
    }

    private function salesDocsCount(int $owner, Carbon $from, Carbon $to): int
    {
        return (int) AccSale::where('network_owner_id', $owner)
            ->where('status', AccSale::STATUS_POSTED)
            ->whereBetween('sold_at', [$from->copy()->startOfDay(), $to->copy()->endOfDay()])
            ->count();
    }

    private function entriesCount(int $owner, Carbon $from, Carbon $to): int
    {
        return (int) AccJournalEntry::where('network_owner_id', $owner)
            ->where('is_posted', true)
            ->whereDate('date', '>=', $from)
            ->whereDate('date', '<=', $to)
            ->count();
    }

    private function cashBlock(int $owner): array
    {
        $boxes = Schema::hasTable('acc_cash_boxes')
            ? DB::table('acc_cash_boxes')
                ->where('network_owner_id', $owner)
                ->where('is_active', true)
                ->orderByDesc('is_default')
                ->orderBy('id')
                ->get(['id', 'name', 'currency', 'balance', 'is_default'])
            : collect();

        $baseTotal = (float) DB::table('acc_balances')
            ->where('network_owner_id', $owner)
            ->where('party_type', 'box')
            ->sum('balance');

        return [
            'base_total' => round($baseTotal, 2),
            'boxes' => $boxes->map(fn ($b) => [
                'id' => $b->id,
                'name' => $b->name,
                'currency' => $b->currency,
                'balance' => (float) $b->balance,
                'is_default' => (bool) $b->is_default,
            ])->values(),
        ];
    }

    /**
     * Party exposure from acc_balances: positive balances are money
     * owed TO the network (receivables), negative are owed BY it.
     */
    private function partyBalances(int $owner): array
    {
        $rows = DB::table('acc_balances')
            ->where('network_owner_id', $owner)
            ->where('party_type', '!=', 'box')
            ->selectRaw('party_type,
                SUM(CASE WHEN balance > 0 THEN balance ELSE 0 END) as owed,
                SUM(CASE WHEN balance < 0 THEN -balance ELSE 0 END) as owing')
            ->groupBy('party_type')
            ->get()
            ->keyBy('party_type');

        $receivables = [
            'pos' => round((float) ($rows['pos']->owed ?? 0), 2),
            'distributor' => round((float) ($rows['distributor']->owed ?? 0), 2),
            'customer' => round((float) ($rows['customer']->owed ?? 0), 2),
        ];
        $liabilities = [
            'supplier' => round((float) ($rows['supplier']->owing ?? 0), 2),
            'pos_profits' => round((float) ($rows['pos']->owing ?? 0), 2),
            'distributor_profits' => round((float) ($rows['distributor']->owing ?? 0), 2),
        ];

        return [
            'receivables' => $receivables,
            'receivables_total' => round(array_sum($receivables), 2),
            'liabilities' => $liabilities,
            'liabilities_total' => round(array_sum($liabilities), 2),
        ];
    }

    private function stockBlock(int $owner): array
    {
        if (! Schema::hasTable('acc_stock')) {
            return ['qty' => 0.0, 'value' => 0.0, 'categories' => 0];
        }

        $row = DB::table('acc_stock')
            ->where('network_owner_id', $owner)
            ->selectRaw('COUNT(*) as cnt, COALESCE(SUM(qty),0) as qty,
                COALESCE(SUM(qty * avg_cost),0) as value')
            ->first();

        return [
            'qty' => round((float) ($row->qty ?? 0), 2),
            'value' => round((float) ($row->value ?? 0), 2),
            'categories' => (int) ($row->cnt ?? 0),
        ];
    }

    private function debtsBlock(int $owner): array
    {
        $row = AccDebt::where('network_owner_id', $owner)
            ->whereIn('status', [AccDebt::STATUS_OPEN, AccDebt::STATUS_PARTIAL])
            ->selectRaw('COUNT(*) as cnt, COALESCE(SUM(base_due - base_paid),0) as remaining')
            ->first();

        return [
            'open_count' => (int) ($row->cnt ?? 0),
            'remaining_base' => round((float) ($row->remaining ?? 0), 2),
        ];
    }

    /** @return array{0: Carbon, 1: Carbon} resolved period. */
    private function period(?string $from, ?string $to): array
    {
        $fromDate = $from ? Carbon::parse($from)->startOfDay() : Carbon::today()->startOfMonth();
        $toDate = $to ? Carbon::parse($to)->endOfDay() : Carbon::today()->endOfDay();

        return [$fromDate, $toDate];
    }
}
