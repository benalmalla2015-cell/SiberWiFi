<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccBalance;
use App\Models\AccCardExchange;
use App\Models\AccCashBox;
use App\Models\AccJournalEntry;
use App\Models\AccPointsLedger;
use App\Models\AccPosPoint;
use App\Models\AccProfitLedger;
use App\Models\AccWithdrawal;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-07 — the POS-agent surface over the real HTTP stack:
 * /pos/home aggregate, profit withdrawals (request → hold →
 * approve/paid/reject/cancel), and instant card-for-points
 * exchange — each money move inside one atomic transaction with a
 * balanced journal entry.
 *
 * Self-contained like the other acc suites: it builds the core
 * schema plus this sprint's 0700* migrations, the real ACC-02/04/05
 * migrations, and minimal card_categories/exchange_rate_settings
 * stand-ins for the FKs.
 */
class AccPosAppTest extends TestCase
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
                $t->string('name');
                $t->softDeletes();
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

        // Real acc migrations, in sprint order.
        foreach (
            [
                '2026_10_26_0100*_create_acc_*.php', // ACC-01 core
                '2026_10_27_0200*_create_acc_*.php', // ACC-03 parties
                '2026_10_27_0300*_create_acc_*.php', // ACC-02 inventory
                '2026_10_27_0400*_create_acc_*.php', // ACC-04 orders+ledgers
                '2026_10_27_0500*_create_acc_*.php', // ACC-05 money
                '2026_10_27_0700*_create_acc_*.php', // ACC-07 this sprint
            ] as $pattern
        ) {
            foreach (glob(database_path('migrations/' . $pattern)) ?: [] as $file) {
                $table = $this->tableOf($file);
                if ($table !== null && ! Schema::hasTable($table)) {
                    (require $file)->up();
                }
            }
        }
    }

    private function tableOf(string $file): ?string
    {
        return preg_match('/create_(acc_\w+)_table\.php$/', $file, $m) ? $m[1] : null;
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

    private function makeCategory(User $owner, float $sell, float $cost, string $name = 'باقة'): int
    {
        return (int) DB::table('acc_card_categories')->insertGetId([
            'network_owner_id' => $owner->id,
            'name' => $name,
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
            'avg_cost' => 0,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    /** A pos agent bound to a point funded with points + profit. */
    private function posFixture(User $owner, float $points = 10000, float $profit = 3000): array
    {
        $user = $this->person('771234001');
        $agent = $this->makeAgent($owner, $user, 'pos');
        $pos = $this->makePos($owner, $agent, [
            'points_balance' => $points,
            'profit_balance' => $profit,
        ]);

        return [$user, $agent, $pos];
    }

    private function balance(User $owner, string $type, int $id): float
    {
        return (float) (AccBalance::where('network_owner_id', $owner->id)
            ->where('party_type', $type)
            ->where('party_id', $id)
            ->value('balance') ?? 0);
    }

    // ── Home ─────────────────────────────────────────────────────

    public function test_pos_home_returns_balances_packages_and_stats(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 600, 'باقة 5 جيجا');
        $this->stock($owner, $catId, 20);
        $this->makeCategory($owner, 500, 300, 'باقة 1 جيجا');

        Sanctum::actingAs($posUser);
        $data = $this->getJson(self::BASE . '/pos/home')->assertOk()->json('data');

        $this->assertSame($pos->id, $data['pos']['id']);
        $this->assertSame(10000.0, (float) $data['pos']['points_balance']);
        $this->assertSame(3000.0, (float) $data['pos']['profit_balance']);
        $this->assertCount(2, $data['packages']);
        // Package prices are server-side — points cost = sell price.
        $pkg = collect($data['packages'])->firstWhere('id', $catId);
        $this->assertSame(1000.0, (float) $pkg['points_cost']);
        $this->assertSame(20.0, (float) $pkg['stock_qty']);
        $this->assertTrue($pkg['available']);
        $this->assertSame(0, $data['stats']['pending_orders']);
        $this->assertArrayHasKey('recent_ledger', $data);
    }

    public function test_pos_home_requires_a_bound_point(): void
    {
        $owner = $this->owner();
        $stray = $this->makeAgent($owner, $this->person('771234009'), 'pos');

        Sanctum::actingAs($stray->user);
        $this->getJson(self::BASE . '/pos/home')
            ->assertForbidden()
            ->assertJsonPath('success', false);
    }

    // ── Withdrawals: request + hold ──────────────────────────────

    public function test_withdrawal_request_holds_profit_atomically(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);
        Sanctum::actingAs($posUser);

        $res = $this->postJson(self::BASE . '/pos/withdrawals', [
            'amount' => 1200,
            'receiver_name' => 'صاحب البقالة',
            'note' => 'سحب نهاية الشهر',
        ]);

        $res->assertCreated()
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.amount', 1200);

        // The hold moved immediately: balance 3000 → 1800 + ledger row.
        $this->assertSame(1800.0, (float) $pos->fresh()->profit_balance);
        $hold = AccProfitLedger::sole();
        $this->assertSame('pos', $hold->party_type);
        $this->assertSame($pos->id, $hold->party_id);
        $this->assertSame('withdrawal', $hold->reason);
        $this->assertSame(-1200.0, (float) $hold->delta);
        $this->assertSame(AccWithdrawal::sole()->id, $hold->ref_id);
    }

    public function test_withdrawal_request_is_idempotent_and_balance_checked(): void
    {
        $owner = $this->owner();
        [$posUser] = $this->posFixture($owner, 10000, 500);
        Sanctum::actingAs($posUser);

        // Over the balance → 422, nothing held.
        $this->postJson(self::BASE . '/pos/withdrawals', ['amount' => 999])
            ->assertUnprocessable();
        $this->assertSame(0, AccWithdrawal::count());
        $this->assertSame(0, AccProfitLedger::count());

        // Same key replays — one row, one hold.
        $payload = ['amount' => 300, 'idempotency_key' => 'wd-001'];
        $first = $this->postJson(self::BASE . '/pos/withdrawals', $payload)->assertCreated();
        $second = $this->postJson(self::BASE . '/pos/withdrawals', $payload)->assertCreated();
        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $this->assertSame(1, AccWithdrawal::count());
        $this->assertSame(1, AccProfitLedger::count());
        $this->assertSame(200.0, (float) AccPosPoint::sole()->profit_balance);
    }

    public function test_withdrawal_full_cycle_pending_approved_paid(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner, 10000, 3000);
        $box = AccCashBox::create([
            'network_owner_id' => $owner->id,
            'name' => 'الرئيسي', 'currency' => 'north',
            'balance' => 5000, 'is_default' => true, 'is_active' => true,
        ]);

        Sanctum::actingAs($posUser);
        $id = $this->postJson(self::BASE . '/pos/withdrawals', ['amount' => 1000])
            ->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/withdrawals/{$id}/approve")
            ->assertOk()->assertJsonPath('data.status', 'approved');
        $this->postJson(self::BASE . "/withdrawals/{$id}/paid", [
            'cash_box_id' => $box->id,
            'receipt_no' => 'RV-77',
        ])->assertOk()->assertJsonPath('data.status', 'paid');

        // Cash left the drawer; the liability was settled by a
        // balanced withdrawal entry.
        $this->assertSame(4000.0, (float) $box->fresh()->balance);
        $entry = AccJournalEntry::where('doc_type', 'withdrawal')->sole();
        $this->assertSame(
            (float) $entry->lines->sum('debit'),
            (float) $entry->lines->sum('credit')
        );
        $this->assertSame(1000.0, (float) $entry->lines->sum('debit'));
        $this->assertSame($id, $entry->doc_ref_id);

        $w = AccWithdrawal::sole();
        $this->assertSame('paid', $w->status);
        $this->assertSame($box->id, $w->cash_box_id);
        $this->assertSame($entry->id, $w->journal_entry_id);
        $this->assertNotNull($w->paid_at);

        // acc_balances mirrors both legs (debit − credit convention):
        // the box's credit shows −1000; the debit to the POS profit
        // liability lands +1000 — it settles accruals posted as credits.
        $this->assertSame(1000.0, $this->balance($owner, 'pos', $pos->id));
        $this->assertSame(-1000.0, $this->balance($owner, 'box', $box->id));

        // Profit stays deducted — the hold was consumed, not refunded.
        $this->assertSame(2000.0, (float) $pos->fresh()->profit_balance);

        // Paid is terminal and replayable.
        $this->postJson(self::BASE . "/withdrawals/{$id}/paid")
            ->assertOk()->assertJsonPath('data.status', 'paid');
        $this->assertSame(1, AccJournalEntry::where('doc_type', 'withdrawal')->count());
    }

    public function test_rejected_withdrawal_refunds_the_hold(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner, 10000, 3000);
        Sanctum::actingAs($posUser);
        $id = $this->postJson(self::BASE . '/pos/withdrawals', ['amount' => 1000])
            ->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/withdrawals/{$id}/reject", [
            'reason' => 'مستند ناقص',
        ])->assertOk()->assertJsonPath('data.status', 'rejected');

        // Hold refunded: balance restored, two ledger rows (−hold +refund).
        $this->assertSame(3000.0, (float) $pos->fresh()->profit_balance);
        $this->assertSame(2, AccProfitLedger::count());
        $refund = AccProfitLedger::latest('id')->first();
        $this->assertSame(1000.0, (float) $refund->delta);

        // Terminal: no approve/pay afterwards; no journal posted.
        $this->postJson(self::BASE . "/withdrawals/{$id}/paid")->assertConflict();
        $this->assertSame(0, AccJournalEntry::where('doc_type', 'withdrawal')->count());
    }

    public function test_pos_cancels_only_own_pending_withdrawal(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner, 10000, 3000);
        $otherUser = $this->person('771234002');
        $otherAgent = $this->makeAgent($owner, $otherUser, 'pos');
        $this->makePos($owner, $otherAgent);

        Sanctum::actingAs($posUser);
        $id = $this->postJson(self::BASE . '/pos/withdrawals', ['amount' => 800])
            ->assertCreated()->json('data.id');

        // Another pos agent cannot reach it (not theirs → 404).
        Sanctum::actingAs($otherUser);
        $this->postJson(self::BASE . "/pos/withdrawals/{$id}/cancel")->assertNotFound();

        Sanctum::actingAs($posUser);
        $this->postJson(self::BASE . "/pos/withdrawals/{$id}/cancel")
            ->assertOk()->assertJsonPath('data.status', 'cancelled');

        $this->assertSame(3000.0, (float) $pos->fresh()->profit_balance);
        // Re-cancel replays; a decided row can't re-cancel.
        $this->postJson(self::BASE . "/pos/withdrawals/{$id}/cancel")
            ->assertOk()->assertJsonPath('data.status', 'cancelled');
        $this->assertSame(2, AccProfitLedger::count());
    }

    public function test_management_lists_withdrawals_with_party_names(): void
    {
        $owner = $this->owner();
        [$posUser] = $this->posFixture($owner);
        Sanctum::actingAs($posUser);
        $this->postJson(self::BASE . '/pos/withdrawals', ['amount' => 700])
            ->assertCreated();

        Sanctum::actingAs($owner);
        $this->getJson(self::BASE . '/withdrawals?status=pending')
            ->assertOk()
            ->assertJsonCount(1, 'data.data')
            ->assertJsonPath('data.data.0.requester_name', 'بقالة النور');
        $this->getJson(self::BASE . '/withdrawals?status=paid')
            ->assertOk()->assertJsonCount(0, 'data.data');
    }

    // ── Exchange ─────────────────────────────────────────────────

    public function test_exchange_spends_points_moves_stock_posts_entry(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner, 10000, 3000);
        $catId = $this->makeCategory($owner, 1000, 600, 'باقة 5 جيجا');
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($posUser);
        $res = $this->postJson(self::BASE . '/pos/exchange-cards', [
            'category_id' => $catId,
            'qty' => 3,
        ]);

        $res->assertCreated()
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.points_spent', 3000)
            ->assertJsonPath('data.category_name', 'باقة 5 جيجا');

        // Points: 10000 − 3000, ledger reason conversion.
        $this->assertSame(7000.0, (float) $pos->fresh()->points_balance);
        $ledger = AccPointsLedger::sole();
        $this->assertSame('conversion', $ledger->reason);
        $this->assertSame(-3000.0, (float) $ledger->delta);
        $this->assertSame(7000.0, (float) $ledger->balance_after);

        // Stock: 10 − 3 = 7 + 'exchange' movement.
        $this->assertSame(7.0, (float) DB::table('acc_stock')->where('category_id', $catId)->value('qty'));
        $mv = DB::table('acc_stock_movements')->sole();
        $this->assertSame('exchange', $mv->type);
        $this->assertSame(-3.0, (float) $mv->qty);
        $this->assertSame('acc_card_exchanges', $mv->ref_type);

        // Balanced pos_sale entry: value 3000 + COGS 1800.
        $entry = AccJournalEntry::where('doc_type', 'pos_sale')->sole();
        $this->assertSame(
            (float) $entry->lines->sum('debit'),
            (float) $entry->lines->sum('credit')
        );
        $this->assertSame(4800.0, (float) $entry->lines->sum('debit'));
        $this->assertSame(AccCardExchange::sole()->journal_entry_id, $entry->id);
    }

    public function test_exchange_rolls_back_on_insufficient_points(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner, 1000, 0); // too few points
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($posUser);
        $this->postJson(self::BASE . '/pos/exchange-cards', [
            'category_id' => $catId, 'qty' => 3, // needs 3000
        ])->assertUnprocessable();

        $this->assertSame(1000.0, (float) $pos->fresh()->points_balance);
        $this->assertSame(10.0, (float) DB::table('acc_stock')->where('category_id', $catId)->value('qty'));
        $this->assertSame(0, AccCardExchange::count());
        $this->assertSame(0, AccPointsLedger::count());
        $this->assertSame(0, DB::table('acc_stock_movements')->count());
        $this->assertSame(0, AccJournalEntry::count());
    }

    public function test_exchange_rolls_back_on_insufficient_stock(): void
    {
        $owner = $this->owner();
        [$posUser] = $this->posFixture($owner, 50000, 0);
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 2);

        Sanctum::actingAs($posUser);
        $this->postJson(self::BASE . '/pos/exchange-cards', [
            'category_id' => $catId, 'qty' => 5,
        ])->assertUnprocessable();

        $this->assertSame(50000.0, (float) AccPosPoint::sole()->points_balance);
        $this->assertSame(2.0, (float) DB::table('acc_stock')->where('category_id', $catId)->value('qty'));
        $this->assertSame(0, AccCardExchange::count());
    }

    public function test_exchange_is_idempotent_by_key(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner, 10000, 0);
        $catId = $this->makeCategory($owner, 500, 300);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($posUser);
        $payload = [
            'category_id' => $catId, 'qty' => 2,
            'idempotency_key' => 'ex-001',
        ];
        $first = $this->postJson(self::BASE . '/pos/exchange-cards', $payload)->assertCreated();
        $second = $this->postJson(self::BASE . '/pos/exchange-cards', $payload)->assertCreated();

        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $this->assertSame(1, AccCardExchange::count());
        $this->assertSame(9000.0, (float) $pos->fresh()->points_balance);
        $this->assertSame(1, AccPointsLedger::count());
        $this->assertSame(1, AccJournalEntry::count());
    }

    public function test_pos_sees_own_exchanges_list(): void
    {
        $owner = $this->owner();
        [$posUser] = $this->posFixture($owner, 10000, 0);
        $catId = $this->makeCategory($owner, 500, 300);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($posUser);
        $this->postJson(self::BASE . '/pos/exchange-cards', [
            'category_id' => $catId, 'qty' => 1,
        ])->assertCreated();

        $this->getJson(self::BASE . '/pos/exchanges')
            ->assertOk()
            ->assertJsonCount(1, 'data.data')
            ->assertJsonPath('data.data.0.points_spent', 500);
    }

    // ── Permissions + isolation ──────────────────────────────────

    public function test_pos_surface_is_for_pos_role_only(): void
    {
        $owner = $this->owner();
        $distUser = $this->person('771234020');
        $this->makeAgent($owner, $distUser, 'distributor');

        Sanctum::actingAs($distUser);
        // Distributor lacks posapp.* — every pos surface is 403.
        $this->getJson(self::BASE . '/pos/home')->assertForbidden();
        $this->postJson(self::BASE . '/pos/exchange-cards', [
            'category_id' => 1, 'qty' => 1,
        ])->assertForbidden();

        // A pos agent cannot reach the management decide path.
        [$posUser] = $this->posFixture($owner);
        Sanctum::actingAs($posUser);
        $id = $this->postJson(self::BASE . '/pos/withdrawals', ['amount' => 100])
            ->assertCreated()->json('data.id');
        $this->getJson(self::BASE . '/withdrawals')->assertForbidden();
        $this->postJson(self::BASE . "/withdrawals/{$id}/approve")->assertForbidden();
    }

    public function test_distributor_withdraws_own_profit_via_dist_alias(): void
    {
        $owner = $this->owner();
        $distUser = $this->person('771234021');
        $dist = $this->makeAgent($owner, $distUser, 'distributor');
        // Seed the distributor's accrued profit in the ledger.
        AccProfitLedger::create([
            'network_owner_id' => $owner->id,
            'party_type' => 'distributor', 'party_id' => $dist->id,
            'reason' => 'sale_commission', 'delta' => 800,
            'created_at' => now(),
        ]);

        Sanctum::actingAs($distUser);
        $id = $this->postJson(self::BASE . '/dist/withdrawals', ['amount' => 500])
            ->assertCreated()->json('data.id');

        $w = AccWithdrawal::sole();
        $this->assertSame('distributor', $w->requester_type);
        $this->assertSame($dist->id, $w->requester_id);
        $this->assertSame(-500.0, (float) AccProfitLedger::latest('id')->value('delta'));

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/withdrawals/{$id}/reject")
            ->assertOk()->assertJsonPath('data.status', 'rejected');
        // Refunded in the ledger → back to 800.
        $this->assertSame(800.0, (float) AccProfitLedger::where('party_type', 'distributor')->sum('delta'));
    }

    public function test_tenant_isolation(): void
    {
        $ownerA = $this->owner('770000001');
        $ownerB = $this->owner('770000002');
        [$posUserA, , $posA] = $this->posFixture($ownerA, 10000, 2000);
        [$posUserB] = $this->posFixture($ownerB, 5000, 1000);

        Sanctum::actingAs($posUserA);
        $idA = $this->postJson(self::BASE . '/pos/withdrawals', ['amount' => 100])
            ->assertCreated()->json('data.id');

        // Owner B sees nothing of owner A and can't decide on it.
        Sanctum::actingAs($ownerB);
        $this->getJson(self::BASE . '/withdrawals')->assertOk()
            ->assertJsonCount(0, 'data.data');
        $this->postJson(self::BASE . "/withdrawals/{$idA}/approve")->assertNotFound();

        // Pos B's home is its own balances only.
        Sanctum::actingAs($posUserB);
        $data = $this->getJson(self::BASE . '/pos/home')->assertOk()->json('data');
        $this->assertSame(5000.0, (float) $data['pos']['points_balance']);
        $this->assertSame(1000.0, (float) $data['pos']['profit_balance']);
    }
}
