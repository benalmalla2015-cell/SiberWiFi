<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccCashBox;
use App\Models\AccCollection;
use App\Models\AccCommission;
use App\Models\AccDebt;
use App\Models\AccJournalEntry;
use App\Models\AccPosOrder;
use App\Models\AccPosPoint;
use App\Models\AccProfitLedger;
use App\Models\AccSale;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-06 — the distributor surface over the real HTTP stack:
 * /dist/home (categories + daily remaining + POS balances),
 * /dist/sale (cash | credit | partial — stock + journal + debt +
 * commission in ONE transaction), /dist/sales, /dist/report,
 * /dist/commissions.
 *
 * Self-contained like the other acc suites: it builds the core
 * ACC-01/03 schema plus the ACC-02/04/05/06 migration sets and a
 * minimal exchange_rate_settings table (read-only, PLAN §2.5).
 */
class AccDistTest extends TestCase
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
        // Platform card_categories — the ACC-02 catalog FK target.
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
        foreach (['0200', '0300', '0400', '0500', '0600'] as $batch) {
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

    private function makePos(User $owner, ?AccAgent $agent = null, array $over = []): AccPosPoint
    {
        return AccPosPoint::create(array_merge([
            'network_owner_id' => $owner->id,
            'agent_id' => $agent?->id,
            'name' => 'بقالة النور',
            'status' => 'active',
        ], $over));
    }

    private function makeCategory(User $owner, float $sell, float $cost): int
    {
        return (int) DB::table('acc_card_categories')->insertGetId([
            'network_owner_id' => $owner->id,
            'name' => 'فئة ' . $sell,
            'sell_price' => $sell,
            'cost_price' => $cost,
            'unit_label' => 'كرت',
            'is_active' => true,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function stock(User $owner, int $categoryId, float $qty): void
    {
        DB::table('acc_stock')->insert([
            'network_owner_id' => $owner->id,
            'category_id' => $categoryId,
            'qty' => $qty,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function stockQty(int $categoryId): float
    {
        return (float) DB::table('acc_stock')->where('category_id', $categoryId)->value('qty');
    }

    /** A distributor user+agent and a sellable POS point. */
    private function distFixture(User $owner, array $agentOver = [], array $posOver = []): array
    {
        $user = $this->person('771234500');
        $agent = $this->makeAgent($owner, $user, 'distributor', array_merge([
            'cash_allowed' => true,
            'credit_allowed' => true,
        ], $agentOver));
        $pos = $this->makePos($owner, null, $posOver);

        return [$user, $agent, $pos];
    }

    private function salePayload(int $posId, int $catId, int $qty, string $kind, array $extra = []): array
    {
        return array_merge([
            'pos_id' => $posId,
            'items' => [['category_id' => $catId, 'qty' => $qty]],
            'payment_kind' => $kind,
        ], $extra);
    }

    // ── Home ─────────────────────────────────────────────────────

    public function test_home_returns_categories_remaining_and_pos_balances(): void
    {
        $owner = $this->owner();
        [$distUser, $agent, $pos] = $this->distFixture($owner);
        $agent->update(['daily_limit_per_category' => []]);
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 20);
        $agent->update(['daily_limit_per_category' => [$catId => 8]]);

        Sanctum::actingAs($distUser);
        $res = $this->getJson(self::BASE . '/dist/home')->assertOk();

        $cat = collect($res->json('data.categories'))->sole('id', $catId);
        $this->assertSame(20.0, (float) $cat['stock_qty']);
        $this->assertSame(8.0, (float) $cat['daily_limit']);
        $this->assertSame(0.0, (float) $cat['sold_today']);
        $this->assertSame(8.0, (float) $cat['remaining_today']);

        $point = collect($res->json('data.pos_points'))->sole('id', $pos->id);
        $this->assertSame(0.0, (float) $point['ar_balance']);
        $this->assertSame($agent->id, $res->json('data.agent.id'));
        $this->assertTrue($res->json('data.agent.cash_allowed'));
    }

    // ── Cash sale ────────────────────────────────────────────────

    public function test_cash_sale_posts_stock_box_journal_and_commission(): void
    {
        $owner = $this->owner();
        [$distUser, $agent, $pos] = $this->distFixture($owner, [
            'commission_mode' => 'percent', 'commission_value' => 10,
        ]);
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($distUser);
        $res = $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 4, 'cash')
        );

        $res->assertCreated()
            ->assertJsonPath('data.payment_kind', 'cash')
            ->assertJsonPath('data.total_amount', 4000)
            ->assertJsonPath('data.paid_amount', 4000);

        $sale = AccSale::sole();
        $this->assertMatchesRegularExpression('/^SA-\d{8}-\d{6}$/', $sale->sale_no);
        $this->assertSame($agent->id, $sale->distributor_id);
        $this->assertSame(400.0, (float) $sale->commission_amount);
        $this->assertNull($sale->debt_id);
        $this->assertNotNull($sale->journal_entry_id);
        $this->assertNotNull($sale->cash_box_id);

        // Stock: 10 − 4 = 6 + a `sale` movement.
        $this->assertSame(6.0, $this->stockQty($catId));
        $movement = DB::table('acc_stock_movements')->sole();
        $this->assertSame('sale', $movement->type);
        $this->assertSame(-4.0, (float) $movement->qty);
        $this->assertSame('acc_sales', $movement->ref_type);
        $this->assertSame($sale->id, (int) $movement->ref_id);

        // Cash box received the paid amount.
        $box = AccCashBox::sole();
        $this->assertTrue($box->is_default);
        $this->assertSame(4000.0, (float) $box->balance);

        // Journal: one balanced `sale` entry.
        $entry = AccJournalEntry::sole();
        $this->assertSame('sale', $entry->doc_type);
        $this->assertSame('sale-' . $sale->id, $entry->idempotency_key);
        $lines = $entry->lines;
        $this->assertEquals((float) $lines->sum('debit'), (float) $lines->sum('credit'));
        // Dr box 4000 + Dr COGS 2400 + Dr commission 400 = 6800
        $this->assertEquals(6800.0, (float) $lines->sum('debit'));
        $cashLeg = $lines->firstWhere('account_code', '1000');
        $this->assertSame(4000.0, (float) $cashLeg->debit);
        $this->assertSame('box', $cashLeg->party_type);

        // Commission: profit ledger + accrued period row.
        $profit = AccProfitLedger::sole();
        $this->assertSame('distributor', $profit->party_type);
        $this->assertSame($agent->id, $profit->party_id);
        $this->assertSame(400.0, (float) $profit->delta);
        $this->assertSame('acc_sales', $profit->ref_type);

        $comm = AccCommission::sole();
        $this->assertSame(now()->format('Y-m'), $comm->period);
        $this->assertSame(4000.0, (float) $comm->sales_amount);
        $this->assertSame(400.0, (float) $comm->commission_amount);
        $this->assertSame('accrued', $comm->status);
    }

    // ── Credit sale → debt ───────────────────────────────────────

    public function test_credit_sale_creates_debt_and_ar_entry_then_settles(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 500, 300);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($distUser);
        $res = $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 3, 'credit', ['due_date' => '2026-11-01'])
        );

        $res->assertCreated()
            ->assertJsonPath('data.paid_amount', 0)
            ->assertJsonPath('data.credit_remaining', 1500);

        $sale = AccSale::sole();
        $debt = AccDebt::sole();
        $this->assertSame($debt->id, $sale->debt_id);
        $this->assertSame('pos', $debt->party_type);
        $this->assertSame($pos->id, $debt->party_id);
        $this->assertSame(1500.0, (float) $debt->amount_due);
        $this->assertSame('open', $debt->status);
        $this->assertSame('2026-11-01', $debt->due_date?->toDateString());

        // AR leg of the sale entry went to the POS party.
        $entry = AccJournalEntry::sole();
        $ar = $entry->lines->firstWhere('account_code', '1200');
        $this->assertNotNull($ar);
        $this->assertSame('pos', $ar->party_type);
        $this->assertSame($pos->id, $ar->party_id);
        $this->assertSame(1500.0, (float) $ar->debit);
        // No cash box row was touched by a pure credit sale.
        $this->assertSame(0, AccCashBox::count());

        // The debt surfaces on /dist/debts and settles atomically.
        $this->getJson(self::BASE . '/dist/debts?status=open')
            ->assertOk()->assertJsonCount(1, 'data.data');
        $this->postJson(self::BASE . "/dist/debts/{$debt->id}/pay", ['amount' => 1500])
            ->assertOk();

        $debt->refresh();
        $this->assertSame('paid', $debt->status);
        $this->assertSame(1, AccCollection::count());
        // Settlement posted a second (collection) entry.
        $this->assertSame(2, AccJournalEntry::count());
    }

    public function test_partial_sale_splits_cash_and_debt(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 5);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 2, 'partial', ['paid_amount' => 800])
        )->assertCreated()
            ->assertJsonPath('data.paid_amount', 800)
            ->assertJsonPath('data.credit_remaining', 1200);

        $sale = AccSale::sole();
        $this->assertSame(1200.0, (float) AccDebt::sole()->amount_due);
        $this->assertSame(800.0, (float) AccCashBox::sole()->balance);
        // The debt's tracker points at the sale's own journal entry.
        $this->assertSame($sale->journal_entry_id, AccDebt::sole()->journal_entry_id);
        $this->assertSame($sale->id, AccJournalEntry::sole()->doc_ref_id);

        $lines = AccJournalEntry::sole()->lines;
        $this->assertSame(800.0, (float) $lines->firstWhere('account_code', '1000')->debit);
        $this->assertSame(1200.0, (float) $lines->firstWhere('account_code', '1200')->debit);
    }

    // ── Limits + policy ──────────────────────────────────────────

    public function test_daily_limit_blocks_excess_sale(): void
    {
        $owner = $this->owner();
        [$distUser, $agent, $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 50);
        $agent->update(['daily_limit_per_category' => [$catId => 5]]);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 6, 'cash')
        )->assertUnprocessable();

        $this->assertSame(0, AccSale::count());
        $this->assertSame(50.0, $this->stockQty($catId));

        // Five is the edge — accepted, then one more is refused.
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 5, 'cash')
        )->assertCreated();
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 1, 'cash')
        )->assertUnprocessable();

        $this->assertSame(1, AccSale::count());
        $this->assertSame(45.0, $this->stockQty($catId));
    }

    public function test_payment_flags_enforced_on_distributor(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner, [
            'cash_allowed' => false, 'credit_allowed' => false,
        ]);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 1, 'cash')
        )->assertForbidden();
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 1, 'credit')
        )->assertForbidden();

        $this->assertSame(0, AccSale::count());
        $this->assertSame(0, AccJournalEntry::count());
    }

    public function test_pos_credit_limit_blocks_sale(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner, [], ['credit_limit' => 1000]);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 2, 'credit')
        )->assertUnprocessable();

        $this->assertSame(0, AccSale::count());
        $this->assertSame(0, AccDebt::count());
    }

    public function test_insufficient_stock_rolls_back_everything(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 1);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 4, 'credit')
        )->assertUnprocessable();

        $this->assertSame(0, AccSale::count());
        $this->assertSame(0, AccDebt::count());
        $this->assertSame(0, AccJournalEntry::count());
        $this->assertSame(0, DB::table('acc_stock_movements')->count());
        $this->assertSame(1.0, $this->stockQty($catId));
    }

    // ── Replay + roles + isolation ───────────────────────────────

    public function test_sale_is_replayable_via_idempotency_key(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($distUser);
        $payload = $this->salePayload($pos->id, $catId, 2, 'cash', [
            'idempotency_key' => 'dist-sale-001',
        ]);
        $first = $this->postJson(self::BASE . '/dist/sale', $payload)->assertCreated();
        $second = $this->postJson(self::BASE . '/dist/sale', $payload)->assertCreated();

        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $this->assertSame(1, AccSale::count());
        $this->assertSame(1, AccJournalEntry::count());
        $this->assertSame(8.0, $this->stockQty($catId));
    }

    public function test_pos_role_cannot_reach_dist_surface(): void
    {
        $owner = $this->owner();
        $posUser = $this->person('771234900');
        $this->makeAgent($owner, $posUser, 'pos');

        Sanctum::actingAs($posUser);
        $this->getJson(self::BASE . '/dist/home')->assertForbidden();
        $this->postJson(self::BASE . '/dist/sale', [
            'pos_id' => 1, 'payment_kind' => 'cash',
            'items' => [['qty' => 1, 'name' => 'x', 'unit_price' => 10]],
        ])->assertForbidden();
    }

    public function test_distributor_cannot_sell_into_another_tenant(): void
    {
        $ownerA = $this->owner('770000001');
        $ownerB = $this->owner('770000002');
        [$distUser] = $this->distFixture($ownerA);
        $foreignPos = $this->makePos($ownerB);
        $catId = $this->makeCategory($ownerA, 1000, 0);
        $this->stock($ownerA, $catId, 10);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($foreignPos->id, $catId, 1, 'cash')
        )->assertUnprocessable();

        $this->assertSame(0, AccSale::count());
    }

    public function test_owner_desk_sale_attributes_distributor_commission(): void
    {
        $owner = $this->owner();
        [, $dist, $pos] = $this->distFixture($owner, [
            'commission_mode' => 'fixed', 'commission_value' => 150,
        ]);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($owner);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 2, 'cash', ['distributor_id' => $dist->id])
        )->assertCreated()->assertJsonPath('data.distributor_id', $dist->id);

        $comm = AccCommission::sole();
        $this->assertSame($dist->id, $comm->distributor_id);
        $this->assertSame(150.0, (float) $comm->commission_amount);

        // Owner-direct sale (no distributor) accrues nothing.
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 1, 'cash')
        )->assertCreated()->assertJsonPath('data.commission_amount', 0);
        $this->assertSame(1, AccCommission::count());
    }

    // ── Register + report + commissions ─────────────────────────

    public function test_sales_list_scopes_to_own_sales(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        [$otherUser] = $this->distFixture($owner, [], ['name' => 'أخرى']);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 1, 'cash')
        )->assertCreated();

        $this->getJson(self::BASE . '/dist/sales')
            ->assertOk()->assertJsonCount(1, 'data.data');

        // The second distributor sees nothing of the first's book.
        Sanctum::actingAs($otherUser);
        $this->getJson(self::BASE . '/dist/sales')
            ->assertOk()->assertJsonCount(0, 'data.data');
    }

    public function test_report_aggregates_sales_collections_and_debts(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 20);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 2, 'cash')
        )->assertCreated();
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 3, 'credit')
        )->assertCreated();
        $this->postJson(self::BASE . '/dist/collections', [
            'party_type' => 'pos', 'party_id' => $pos->id, 'amount' => 500,
        ])->assertCreated();

        $res = $this->getJson(self::BASE . '/dist/report')->assertOk();
        $totals = $res->json('data.totals');
        $this->assertSame(2, $totals['sales_count']);
        $this->assertSame(5000.0, (float) $totals['sales_total']);
        $this->assertSame(2000.0, (float) $totals['cash_total']);
        $this->assertSame(3000.0, (float) $totals['credit_total']);
        $this->assertSame(500.0, (float) $totals['collections_total']);
        $this->assertSame(1, $totals['open_debts_count']);
        $this->assertSame(3000.0, (float) $totals['open_debts_remaining']);

        $cats = collect($res->json('data.categories'));
        $this->assertSame(5.0, (float) $cats->sole('category_id', $catId)['qty']);
    }

    public function test_commissions_endpoint_lists_accrued_periods(): void
    {
        $owner = $this->owner();
        [$distUser, $agent, $pos] = $this->distFixture($owner, [
            'commission_mode' => 'percent', 'commission_value' => 10,
        ]);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 2, 'cash')
        )->assertCreated();
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 3, 'cash')
        )->assertCreated();

        $res = $this->getJson(self::BASE . '/dist/commissions')->assertOk();
        $row = collect($res->json('data'))->sole('period', now()->format('Y-m'));
        $this->assertSame($agent->id, $row['distributor_id']);
        $this->assertSame(5000.0, (float) $row['sales_amount']);
        $this->assertSame(500.0, (float) $row['commission_amount']);
        $this->assertSame('accrued', $row['status']);
    }

    public function test_pos_order_approval_accrues_into_commissions(): void
    {
        $owner = $this->owner();
        [$distUser, $dist] = $this->distFixture($owner, [
            'commission_mode' => 'percent', 'commission_value' => 10,
        ]);
        $posUser = $this->person('771234999');
        $posAgent = $this->makeAgent($owner, $posUser, 'pos');
        $pos = $this->makePos($owner, $posAgent, ['points_balance' => 10000]);
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($posUser);
        $orderId = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [['category_id' => $catId, 'qty' => 2]],
            'points_total' => 2000,
            'distributor_id' => $dist->id,
        ])->assertCreated()->json('data.id');

        Sanctum::actingAs($distUser);
        $this->postJson(self::BASE . "/dist/pos-orders/{$orderId}/approve")->assertOk();

        $comm = AccCommission::sole();
        $this->assertSame($dist->id, $comm->distributor_id);
        $this->assertSame(2000.0, (float) $comm->sales_amount);
        $this->assertSame(200.0, (float) $comm->commission_amount);
    }
}
