<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\AccJournalEntry;
use App\Models\AccPosPoint;
use App\Models\AccSale;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-09 — the reporting layer over the real HTTP stack:
 * executive summary, 30-day trend, sales report, POS performance,
 * commissions, daily collections statement, journal browser and
 * audit log. Acceptance rule: every money figure must reconcile
 * with acc_journal_lines 100% — the service aggregates the
 * entries themselves.
 *
 * Self-contained like the other acc suites: builds the core
 * schema plus every acc_* migration batch through 0600.
 */
class AccReportsTest extends TestCase
{
    private const BASE = '/api/network-owner/accounting';

    protected function setUp(): void
    {
        parent::setUp();
        $this->createSchema();
    }

    private function createSchema(): void
    {
        if (! Schema::hasTable('users')) {
            Schema::create('users', function (Blueprint $t) {
                $t->id();
                $t->string('name');
                $t->string('email')->unique();
                $t->string('phone')->nullable();
                $t->string('type')->nullable();
                $t->boolean('is_active')->default(true);
                $t->timestamp('email_verified_at')->nullable();
                $t->string('password');
                $t->rememberToken();
                $t->timestamps();
                $t->softDeletes();
            });
        }
        if (! Schema::hasTable('networks')) {
            Schema::create('networks', function (Blueprint $t) {
                $t->id();
                $t->foreignId('user_id');
                $t->softDeletes();
            });
        }
        if (! Schema::hasTable('network_owners')) {
            Schema::create('network_owners', function (Blueprint $t) {
                $t->id();
                $t->foreignId('user_id');
                $t->softDeletes();
            });
        }
        if (! Schema::hasTable('card_categories')) {
            Schema::create('card_categories', function (Blueprint $t) {
                $t->id();
                $t->foreignId('network_id');
                $t->string('name');
                $t->decimal('price', 12, 2)->default(0);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('exchange_rate_settings')) {
            Schema::create('exchange_rate_settings', function (Blueprint $t) {
                $t->id();
                $t->enum('base_currency', ['north', 'south'])->default('north');
                $t->decimal('rate_percent', 10, 4)->default(100);
                $t->text('description')->nullable();
                $t->boolean('is_active')->default(true);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('acc_journal_entries')) {
            foreach (
                glob(database_path('migrations/2026_10_26_0100*_create_acc_*.php'))
                as $file
            ) {
                (require $file)->up();
            }
        }
        foreach (['0200', '0300', '0400', '0500', '0600', '0700'] as $batch) {
            foreach (
                glob(database_path("migrations/2026_10_27_{$batch}*_create_acc_*.php")) ?: []
                as $file
            ) {
                (require $file)->up();
            }
        }
    }

    // ── Fixtures ─────────────────────────────────────────────────

    private function owner(string $phone = '770000001'): User
    {
        return User::factory()->create([
            'type' => 'network_owner', 'phone' => $phone, 'is_active' => true,
        ]);
    }

    private function person(string $phone): User
    {
        return User::factory()->create([
            'type' => 'customer', 'phone' => $phone, 'is_active' => true,
        ]);
    }

    private function makeAgent(User $owner, User $user, string $role, array $over = []): AccAgent
    {
        return AccAgent::create(array_merge([
            'network_owner_id' => $owner->id,
            'user_id' => $user->id,
            'role' => $role,
            'display_name' => $user->name,
            'status' => 'active',
        ], $over));
    }

    private function makePos(User $owner, string $name = 'بقالة النور'): AccPosPoint
    {
        return AccPosPoint::create([
            'network_owner_id' => $owner->id,
            'name' => $name,
            'status' => 'active',
        ]);
    }

    /** Sum one leg side of a doc_type straight from the books. */
    private function journalLegSum(
        User $owner, string $docType, string $account, string $side
    ): float {
        return (float) DB::table('acc_journal_lines')
            ->join('acc_journal_entries', 'acc_journal_lines.entry_id', '=', 'acc_journal_entries.id')
            ->where('acc_journal_entries.network_owner_id', $owner->id)
            ->where('acc_journal_entries.doc_type', $docType)
            ->where('acc_journal_lines.account_code', $account)
            ->sum('acc_journal_lines.' . $side);
    }

    private function netAccount(User $owner, string $code): float
    {
        $row = DB::table('acc_journal_lines')
            ->join('acc_journal_entries', 'acc_journal_lines.entry_id', '=', 'acc_journal_entries.id')
            ->where('acc_journal_entries.network_owner_id', $owner->id)
            ->where('acc_journal_lines.account_code', $code)
            ->selectRaw('SUM(acc_journal_lines.credit - acc_journal_lines.debit) as n')
            ->first();

        return round((float) ($row->n ?? 0), 2);
    }

    // ── Summary ──────────────────────────────────────────────────

    public function test_summary_figures_match_journal_legs(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        Sanctum::actingAs($owner);

        // Box with opening balance → Dr box / Cr equity.
        $boxId = $this->postJson(self::BASE . '/cash-boxes', [
            'name' => 'الرئيسي', 'opening_balance' => 10000,
        ])->assertCreated()->json('data.id');

        // A cash sale to the POS — free-form item (no catalog row).
        $this->postJson(self::BASE . '/dist/sale', [
            'pos_id' => $pos->id,
            'items' => [['name' => 'كرت ساعة', 'qty' => 10, 'unit_price' => 500, 'unit_cost' => 300]],
            'payment_kind' => 'cash',
            'cash_box_id' => $boxId,
        ])->assertCreated();

        // A collection + an expense.
        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos', 'party_id' => $pos->id, 'amount' => 2000,
            'cash_box_id' => $boxId,
        ])->assertCreated();
        $this->postJson(self::BASE . '/expenses', [
            'category_name' => 'وقود', 'amount' => 700, 'cash_box_id' => $boxId,
        ])->assertCreated();

        $s = $this->getJson(self::BASE . '/summary')
            ->assertOk()->assertJsonPath('success', true)->json('data');

        // Today: sale revenue 5000, collection 2000, expense 700 —
        // each equals its journal legs, not a second opinion.
        $this->assertSame(5000.0, (float) $s['today']['sales']);
        $this->assertSame(2000.0, (float) $s['today']['collections']);
        $this->assertSame(700.0, (float) $s['today']['expenses']);

        // Month revenue = net credit on 4000+4100; expenses = net
        // debit on 5000 (COGS 3000 + fuel 700 + commission 0).
        $this->assertSame(5000.0, (float) $s['month']['revenue']);
        $this->assertSame(3700.0, (float) $s['month']['expenses']);
        $this->assertSame(1300.0, (float) $s['month']['operating_result']);

        // Cash: box holds 10000+5000+2000-700 in its own currency;
        // acc_balances mirrors the same in base.
        $this->assertSame(16300.0, (float) $s['cash']['base_total']);

        // The paid sale left no AR; collection went to a zero-debt POS.
        $this->assertSame(0.0, (float) $s['parties']['receivables']['pos']);

        // Same figures straight from the lines — the match contract.
        $this->assertSame(5000.0, $this->netAccount($owner, '4000'));
        $this->assertSame(3700.0, -$this->netAccount($owner, '5000'));
        $this->assertSame(2000.0, $this->journalLegSum($owner, 'collection', '1000', 'debit'));
    }

    // ── Trend ────────────────────────────────────────────────────

    public function test_trend_returns_daily_journal_series(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/dist/sale', [
            'pos_id' => $pos->id,
            'items' => [['name' => 'كرت', 'qty' => 2, 'unit_price' => 1000]],
            'payment_kind' => 'cash',
        ])->assertCreated();
        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos', 'party_id' => $pos->id, 'amount' => 400,
        ])->assertCreated();

        $data = $this->getJson(self::BASE . '/dashboard/trend?days=30')
            ->assertOk()->json('data');

        $this->assertCount(30, $data['points']);
        $today = collect($data['points'])->firstWhere('date', now()->toDateString());
        $this->assertSame(2000.0, (float) $today['sales']);
        $this->assertSame(400.0, (float) $today['collections']);
        // All other days are zero-filled.
        $this->assertSame(
            2000.0,
            round(collect($data['points'])->sum('sales'), 2)
        );
    }

    // ── Sales report ─────────────────────────────────────────────

    public function test_sales_report_ties_documents_to_journal(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        $distUser = $this->person('771234012');
        $dist = $this->makeAgent($owner, $distUser, 'distributor', [
            'commission_mode' => 'percent', 'commission_value' => 10,
            'credit_allowed' => true,
        ]);
        Sanctum::actingAs($owner);

        // Cash sale via the distributor (10% commission) + credit sale.
        $this->postJson(self::BASE . '/dist/sale', [
            'pos_id' => $pos->id,
            'distributor_id' => $dist->id,
            'items' => [['name' => 'كرت يوم', 'qty' => 5, 'unit_price' => 2000]],
            'payment_kind' => 'cash',
        ])->assertCreated();
        $this->postJson(self::BASE . '/dist/sale', [
            'pos_id' => $pos->id,
            'items' => [['name' => 'كرت أسبوع', 'qty' => 2, 'unit_price' => 6000]],
            'payment_kind' => 'credit',
        ])->assertCreated();

        $data = $this->getJson(self::BASE . '/reports/sales')
            ->assertOk()->json('data');

        $this->assertSame(2, $data['totals']['count']);
        $this->assertSame(22000.0, (float) $data['totals']['total']);
        $this->assertSame(10000.0, (float) $data['totals']['paid']);
        $this->assertSame(12000.0, (float) $data['totals']['credit']);
        $this->assertSame(1000.0, (float) $data['totals']['commission']);

        // The journal block: sale docs credited exactly the same 22000
        // — the «تطابق القيود» rule, surfaced to the client.
        $saleDoc = collect($data['journal']['revenue_by_doc'])
            ->firstWhere('doc_type', 'sale');
        $this->assertSame(22000.0, (float) $saleDoc['amount']);
        $this->assertSame(
            round((float) $data['totals']['total'], 2),
            round((float) $data['journal']['revenue_total'], 2)
        );

        // Slices.
        $this->assertSame(1, collect($data['by_pos'])->count());
        $this->assertSame(2, collect($data['by_category'])->count());
        $this->assertSame(2, collect($data['by_distributor'])->count());
    }

    // ── POS performance ──────────────────────────────────────────

    public function test_pos_performance_scores_and_tiers(): void
    {
        $owner = $this->owner();
        $busy = $this->makePos($owner, 'النقطة النشطة');
        $idle = $this->makePos($owner, 'النقطة الخاملة');
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/dist/sale', [
            'pos_id' => $busy->id,
            'items' => [['name' => 'كرت', 'qty' => 4, 'unit_price' => 3000]],
            'payment_kind' => 'credit',
        ])->assertCreated();
        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos', 'party_id' => $busy->id, 'amount' => 5000,
        ])->assertCreated();

        $data = $this->getJson(self::BASE . '/reports/pos-performance?days=30')
            ->assertOk()->json('data');

        $this->assertCount(2, $data['points']);
        $top = $data['points'][0];
        $this->assertSame($busy->id, $top['pos_id']);
        $this->assertSame(100, $top['score']);
        $this->assertSame('strong', $top['tier']);
        $this->assertSame(12000.0, (float) $top['sales_total']);
        $this->assertSame(5000.0, (float) $top['collections_total']);
        // Credit sale 12000 − collection 5000 → AR 7000.
        $this->assertSame(7000.0, (float) $top['ar_balance']);

        $last = $data['points'][1];
        $this->assertSame($idle->id, $last['pos_id']);
        $this->assertSame('dormant', $last['tier']);
        $this->assertSame(0, $last['score']);
    }

    // ── Commissions ──────────────────────────────────────────────

    public function test_commissions_report_reconciles_with_journal(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        $distUser = $this->person('771234013');
        $dist = $this->makeAgent($owner, $distUser, 'distributor', [
            'commission_mode' => 'percent', 'commission_value' => 10,
            'cash_allowed' => true,
        ]);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/dist/sale', [
            'pos_id' => $pos->id,
            'distributor_id' => $dist->id,
            'items' => [['name' => 'كرت', 'qty' => 10, 'unit_price' => 1000]],
            'payment_kind' => 'cash',
        ])->assertCreated();

        $data = $this->getJson(self::BASE . '/reports/distributor-commissions')
            ->assertOk()->json('data');

        $this->assertSame(1000.0, (float) $data['totals']['commission_amount']);
        $row = collect($data['by_distributor'])->firstWhere('distributor_id', $dist->id);
        $this->assertSame(1000.0, (float) $row['commission_amount']);
        // The POS_PROFITS credit leg posted the same 1000.
        $this->assertSame(1000.0, (float) $row['journal_net']);
    }

    // ── Daily collections statement ──────────────────────────────

    public function test_collections_daily_statement_matches_journal(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos', 'party_id' => $pos->id, 'amount' => 3000,
        ])->assertCreated();
        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'person', 'party_name' => 'تاجر', 'amount' => 1500,
        ])->assertCreated();

        $data = $this->getJson(self::BASE . '/reports/collections-daily')
            ->assertOk()->json('data');

        $this->assertSame(now()->toDateString(), $data['date']);
        $this->assertSame(2, $data['totals']['count']);
        $this->assertSame(4500.0, (float) $data['totals']['total_base']);
        // Journal side: collection-doc box debits for the day.
        $this->assertSame(4500.0, (float) $data['totals']['journal_base']);
        $this->assertCount(2, $data['rows']);
        $this->assertCount(1, $data['by_currency']);
    }

    // ── Journal browser ──────────────────────────────────────────

    public function test_journal_index_show_and_totals(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos', 'party_id' => $pos->id, 'amount' => 8000,
        ])->assertCreated();
        $this->postJson(self::BASE . '/expenses', [
            'category_name' => 'صيانة', 'amount' => 500,
        ])->assertCreated();

        $data = $this->getJson(self::BASE . '/journal')
            ->assertOk()->json('data');

        // Filtered totals balance by construction.
        $this->assertSame(
            round((float) $data['totals']['debit'], 2),
            round((float) $data['totals']['credit'], 2)
        );
        $this->assertSame(8500.0, (float) $data['totals']['debit']);

        // doc_type filter narrows to one entry.
        $filtered = $this->getJson(self::BASE . '/journal?doc_type=expense')
            ->assertOk()->json('data');
        $this->assertCount(1, $filtered['entries']['data']);
        $entryId = $filtered['entries']['data'][0]['id'];

        $show = $this->getJson(self::BASE . "/journal/{$entryId}")
            ->assertOk()->json('data');
        $this->assertSame('expense', $show['doc_type']);
        $this->assertCount(2, $show['lines']);
        $this->assertSame(
            collect($show['lines'])->sum('debit'),
            collect($show['lines'])->sum('credit')
        );
        $expenseLeg = collect($show['lines'])->firstWhere('account_code', '5000');
        $this->assertSame('مصروفات', $expenseLeg['account_name']);
        $this->assertSame(500.0, (float) $expenseLeg['debit']);
    }

    // ── Audit log ────────────────────────────────────────────────

    public function test_audit_log_filters_and_paginates(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos', 'party_id' => $pos->id, 'amount' => 100,
        ])->assertCreated();
        $this->postJson(self::BASE . '/expenses', [
            'category_name' => 'أخرى', 'amount' => 50,
        ])->assertCreated();

        $data = $this->getJson(self::BASE . '/audit-log')
            ->assertOk()->json('data');
        $this->assertGreaterThanOrEqual(4, $data['total']); // posts + doc audits

        $filtered = $this->getJson(self::BASE . '/audit-log?entity=acc_collections')
            ->assertOk()->json('data');
        foreach ($filtered['data'] as $row) {
            $this->assertSame('acc_collections', $row['entity']);
        }
        $this->assertNotEmpty($filtered['data']);
        $this->assertArrayHasKey('meta', $filtered['data'][0]);
    }

    // ── Isolation + role gates ───────────────────────────────────

    public function test_reports_are_tenant_scoped_and_role_gated(): void
    {
        $owner = $this->owner();
        $other = $this->owner('770000002');
        $pos = $this->makePos($owner);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos', 'party_id' => $pos->id, 'amount' => 9000,
        ])->assertCreated();

        // The other owner sees an empty book.
        Sanctum::actingAs($other);
        $this->getJson(self::BASE . '/summary')
            ->assertOk()->assertJsonPath('data.today.collections', 0);
        $this->getJson(self::BASE . '/journal')
            ->assertOk()->assertJsonPath('data.totals.debit', 0);
        $entry = AccJournalEntry::where('network_owner_id', $owner->id)->sole();
        $this->getJson(self::BASE . "/journal/{$entry->id}")->assertNotFound();

        // A pos agent has no reports.* / journal.* / audit.* grants.
        $posUser = $this->person('771234014');
        $this->makeAgent($owner, $posUser, 'pos');
        Sanctum::actingAs($posUser);
        $this->getJson(self::BASE . '/summary')->assertForbidden();
        $this->getJson(self::BASE . '/journal')->assertForbidden();
        $this->getJson(self::BASE . '/audit-log')->assertForbidden();
        $this->getJson(self::BASE . '/reports/sales')->assertForbidden();

        // A distributor is a field role — reports stay manager-side.
        $distUser = $this->person('771234015');
        $this->makeAgent($owner, $distUser, 'distributor');
        Sanctum::actingAs($distUser);
        $this->getJson(self::BASE . '/summary')->assertForbidden();
        $this->assertNotNull(AccAuditLog::first());
        $this->assertNotNull(AccSale::first() ?? AccJournalEntry::first());
    }
}
