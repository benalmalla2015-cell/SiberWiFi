<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccBalance;
use App\Models\AccCashBox;
use App\Models\AccCashTransfer;
use App\Models\AccCollection;
use App\Models\AccDebt;
use App\Models\AccDebtPayment;
use App\Models\AccExpense;
use App\Models\AccExpenseCategory;
use App\Models\AccJournalEntry;
use App\Models\AccPosPoint;
use App\Models\User;
use App\Services\AccContext;
use App\Services\AccMoneyService;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-05 — the money-movement cycle over the real HTTP stack:
 * collections, debts + settlement, cash boxes + transfers, and
 * expenses — each posting a balanced journal entry atomically.
 *
 * Self-contained like the other acc suites: it builds the core
 * ACC-01/03 schema plus this sprint's 05000* migrations, and a
 * minimal exchange_rate_settings table (read-only, PLAN §2.5).
 */
class AccMoneyMovementTest extends TestCase
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
        if (! Schema::hasTable('acc_journal_entries')) {
            foreach (
                glob(database_path('migrations/2026_10_26_0100*_create_acc_*.php'))
                as $file
            ) {
                (require $file)->up();
            }
        }
        if (! Schema::hasTable('acc_agents')) {
            foreach (
                glob(database_path('migrations/2026_10_27_0200*_create_acc_*.php')) ?: []
                as $file
            ) {
                (require $file)->up();
            }
        }
        if (! Schema::hasTable('acc_cash_boxes')) {
            foreach (
                glob(database_path('migrations/2026_10_27_0500*_create_acc_*.php')) ?: []
                as $file
            ) {
                (require $file)->up();
            }
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
        if (! Schema::hasTable('acc_suppliers')) {
            Schema::create('acc_suppliers', function (Blueprint $t) {
                $t->id();
                $t->foreignId('network_owner_id');
                $t->string('name');
                $t->timestamps();
            });
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

    /** Boxes go through the service — an opening balance books Dr box / Cr equity. */
    private function box(User $owner, string $name, string $currency = 'north', float $balance = 0): AccCashBox
    {
        return app(AccMoneyService::class)->createBox(
            AccContext::forUser($owner),
            ['name' => $name, 'currency' => $currency, 'opening_balance' => $balance]
        );
    }

    private function balance(User $owner, string $type, int $id): float
    {
        return (float) (AccBalance::where('network_owner_id', $owner->id)
            ->where('party_type', $type)
            ->where('party_id', $id)
            ->value('balance') ?? 0);
    }

    // ── Collections ──────────────────────────────────────────────

    public function test_collection_posts_balanced_entry_and_funds_box(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        $box = $this->box($owner, 'الرئيسي', 'north', 1000);
        Sanctum::actingAs($owner);

        $res = $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos',
            'party_id' => $pos->id,
            'amount' => 5000,
            'cash_box_id' => $box->id,
            'note' => 'تسوية أسبوعية',
        ]);

        $res->assertCreated()
            ->assertJsonPath('data.party_type', 'pos')
            ->assertJsonPath('data.amount', 5000);

        $this->assertSame(6000.0, (float) $box->fresh()->balance);

        $entry = AccJournalEntry::where('doc_type', 'collection')->sole();
        $this->assertSame(
            (float) $entry->lines->sum('debit'),
            (float) $entry->lines->sum('credit')
        );
        $this->assertSame(5000.0, (float) $entry->lines->sum('debit'));

        // acc_balances mirrors both legs — opening 1000 + 5000 in.
        $this->assertSame(6000.0, $this->balance($owner, 'box', $box->id));
        $this->assertSame(-5000.0, $this->balance($owner, 'pos', $pos->id));

        $collection = AccCollection::sole();
        $this->assertSame($entry->id, $collection->journal_entry_id);
        $this->assertSame($pos->name, $collection->party_name);
    }

    public function test_collection_is_idempotent_by_key(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $payload = [
            'party_type' => 'person',
            'party_name' => 'أحمد',
            'amount' => 2000,
            'idempotency_key' => 'col-001',
        ];

        $first = $this->postJson(self::BASE . '/collections', $payload)->assertCreated();
        $second = $this->postJson(self::BASE . '/collections', $payload)->assertCreated();

        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $this->assertSame(1, AccCollection::count());
        $this->assertSame(1, AccJournalEntry::count());
    }

    public function test_collection_auto_creates_default_box(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'customer',
            'party_name' => 'زبون',
            'amount' => 300,
        ])->assertCreated();

        $box = AccCashBox::sole();
        $this->assertTrue($box->is_default);
        $this->assertSame(300.0, (float) $box->balance);
    }

    // ── Debts ────────────────────────────────────────────────────

    public function test_debt_create_posts_opening_entry_and_pay_settles(): void
    {
        $owner = $this->owner();
        $pos = $this->makePos($owner);
        $box = $this->box($owner, 'الرئيسي', 'north', 0);
        Sanctum::actingAs($owner);

        $debtId = $this->postJson(self::BASE . '/debts', [
            'party_type' => 'pos',
            'party_id' => $pos->id,
            'amount_due' => 10000,
            'due_date' => '2026-11-01',
        ])->assertCreated()->json('data.id');

        // Opening entry: Dr AR pos / Cr equity.
        $opening = AccJournalEntry::where('doc_type', 'adjustment')->sole();
        $this->assertSame(10000.0, $this->balance($owner, 'pos', $pos->id));

        // Partial payment.
        $this->postJson(self::BASE . "/debts/{$debtId}/pay", [
            'amount' => 4000,
            'cash_box_id' => $box->id,
        ])->assertOk()->assertJsonPath('data.debt.status', 'partial');

        $this->assertSame(4000.0, (float) $box->fresh()->balance);
        $this->assertSame(6000.0, $this->balance($owner, 'pos', $pos->id));

        // Settle the rest → paid.
        $this->postJson(self::BASE . "/debts/{$debtId}/pay", [
            'amount' => 6000,
            'cash_box_id' => $box->id,
        ])->assertOk()->assertJsonPath('data.debt.status', 'paid');

        $debt = AccDebt::sole();
        $this->assertSame('paid', $debt->status);
        $this->assertSame(10000.0, (float) $debt->amount_paid);
        $this->assertSame(0.0, $debt->remaining());
        $this->assertSame(2, AccDebtPayment::count());
        $this->assertSame(2, AccCollection::count());
        $this->assertSame(10000.0, (float) $box->fresh()->balance);
        $this->assertSame(0.0, $this->balance($owner, 'pos', $pos->id));

        // Further payments are rejected.
        $this->postJson(self::BASE . "/debts/{$debtId}/pay", ['amount' => 1])
            ->assertConflict();
    }

    public function test_overpayment_and_named_party_debt(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $debtId = $this->postJson(self::BASE . '/debts', [
            'party_type' => 'person',
            'party_name' => 'سالم',
            'phone' => '777000111',
            'amount_due' => 1500,
        ])->assertCreated()->json('data.id');

        $debt = AccDebt::sole();
        // Named parties self-reference for per-debt balance tracking.
        $this->assertSame($debt->id, $debt->party_id);
        $this->assertSame(1500.0, $this->balance($owner, 'customer', $debt->id));

        $this->postJson(self::BASE . "/debts/{$debtId}/pay", ['amount' => 2000])
            ->assertUnprocessable();
        $this->assertSame('open', $debt->fresh()->status);
    }

    public function test_supplier_debt_is_payable_and_pays_out_of_box(): void
    {
        $owner = $this->owner();
        $box = $this->box($owner, 'الرئيسي', 'north', 8000);
        Sanctum::actingAs($owner);

        $debtId = $this->postJson(self::BASE . '/debts', [
            'party_type' => 'supplier',
            'party_name' => 'مورد الكروت',
            'amount_due' => 5000,
        ])->assertCreated()->json('data.id');

        $this->assertSame(-5000.0, $this->balance($owner, 'supplier', AccDebt::sole()->party_id));

        $this->postJson(self::BASE . "/debts/{$debtId}/pay", [
            'amount' => 5000,
            'cash_box_id' => $box->id,
        ])->assertOk()->assertJsonPath('data.debt.status', 'paid');

        $this->assertSame(3000.0, (float) $box->fresh()->balance);
        $this->assertSame(0, AccCollection::count()); // outflow — not a collection
    }

    // ── Cash boxes + transfers ───────────────────────────────────

    public function test_transfer_moves_balance_and_posts_transfer_entry(): void
    {
        $owner = $this->owner();
        $from = $this->box($owner, 'الرئيسي', 'north', 7000);
        $to = $this->box($owner, 'الفرعي', 'north', 500);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/cash-boxes/transfer', [
            'from_box_id' => $from->id,
            'to_box_id' => $to->id,
            'amount' => 2000,
            'note' => 'تغذية الفرع',
        ])->assertCreated();

        $this->assertSame(5000.0, (float) $from->fresh()->balance);
        $this->assertSame(2500.0, (float) $to->fresh()->balance);

        $entry = AccJournalEntry::where('doc_type', 'transfer')->sole();
        $this->assertSame(
            (float) $entry->lines->sum('debit'),
            (float) $entry->lines->sum('credit')
        );
        $this->assertSame(5000.0, $this->balance($owner, 'box', $from->id));
        $this->assertSame(2500.0, $this->balance($owner, 'box', $to->id));
    }

    public function test_transfer_rejects_insufficient_funds(): void
    {
        $owner = $this->owner();
        $from = $this->box($owner, 'الفارغ', 'north', 100);
        $to = $this->box($owner, 'الهدف', 'north', 0);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/cash-boxes/transfer', [
            'from_box_id' => $from->id,
            'to_box_id' => $to->id,
            'amount' => 500,
        ])->assertUnprocessable();

        $this->assertSame(100.0, (float) $from->fresh()->balance);
        $this->assertSame(0, AccCashTransfer::count());
        $this->assertSame(0, AccJournalEntry::where('doc_type', 'transfer')->count());
    }

    public function test_cross_currency_transfer_converts_amounts(): void
    {
        $owner = $this->owner();
        DB::table('exchange_rate_settings')->insert([
            'base_currency' => 'north',
            'rate_percent' => 400, // 1 north = 4 south
            'is_active' => true,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $from = $this->box($owner, 'شمال', 'north', 1000);
        $to = $this->box($owner, 'جنوب', 'south', 0);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/cash-boxes/transfer', [
            'from_box_id' => $from->id,
            'to_box_id' => $to->id,
            'amount' => 100, // north → 400 south arrives
        ])->assertCreated()->assertJsonPath('data.to_amount', 400);

        $this->assertSame(900.0, (float) $from->fresh()->balance);
        $this->assertSame(400.0, (float) $to->fresh()->balance);
        // Journal posts both legs in base (north).
        $entry = AccJournalEntry::where('doc_type', 'transfer')->sole();
        $this->assertSame(100.0, (float) $entry->lines->sum('debit'));
    }

    // ── Expenses ─────────────────────────────────────────────────

    public function test_expense_posts_entry_and_voids_by_reversal(): void
    {
        $owner = $this->owner();
        $box = $this->box($owner, 'الرئيسي', 'north', 5000);
        Sanctum::actingAs($owner);

        // Categories seed lazily on first read.
        $categories = $this->getJson(self::BASE . '/expense-categories')
            ->assertOk()->json('data');
        $this->assertNotEmpty($categories);

        $expenseId = $this->postJson(self::BASE . '/expenses', [
            'category_name' => 'وقود ومولدة',
            'amount' => 1500,
            'cash_box_id' => $box->id,
        ])->assertCreated()->json('data.id');

        $this->assertSame(3500.0, (float) $box->fresh()->balance);
        $entry = AccJournalEntry::where('doc_type', 'expense')->sole();

        // Void → reversal entry restores the box.
        $this->deleteJson(self::BASE . "/expenses/{$expenseId}")
            ->assertOk()->assertJsonPath('data.status', 'void');

        $this->assertSame(5000.0, (float) $box->fresh()->balance);
        $reversal = AccJournalEntry::whereNotNull('reversal_of_id')->sole();
        $this->assertSame($entry->id, $reversal->reversal_of_id);
        $this->assertSame('void', AccExpense::sole()->status);
    }

    public function test_expense_category_crud(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $catId = $this->postJson(self::BASE . '/expense-categories', [
            'name' => 'سفر ونقل',
        ])->assertCreated()->json('data.id');

        $this->postJson(self::BASE . '/expense-categories', ['name' => 'سفر ونقل'])
            ->assertUnprocessable();

        $this->deleteJson(self::BASE . "/expense-categories/{$catId}")->assertOk();
        $cat = AccExpenseCategory::find($catId);
        $this->assertFalse($cat->is_active);

        // Inactive categories can't be used.
        $this->postJson(self::BASE . '/expenses', [
            'category_id' => $catId,
            'amount' => 100,
        ])->assertUnprocessable();
    }

    // ── Multi-currency (ExchangeRateSetting read-only) ───────────

    public function test_south_currency_collection_normalizes_to_base(): void
    {
        $owner = $this->owner();
        DB::table('exchange_rate_settings')->insert([
            'base_currency' => 'north',
            'rate_percent' => 500, // 1 north = 5 south
            'is_active' => true,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $box = $this->box($owner, 'جنوبي', 'south', 0);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'person',
            'party_name' => 'تاجر',
            'amount' => 2500, // south = 500 north base
            'currency' => 'south',
            'cash_box_id' => $box->id,
        ])->assertCreated()->assertJsonPath('data.base_amount', 500);

        // Box counts in south; journal counts in north base.
        $this->assertSame(2500.0, (float) $box->fresh()->balance);
        $entry = AccJournalEntry::where('doc_type', 'collection')->sole();
        $this->assertSame(500.0, (float) $entry->lines->sum('debit'));
    }

    public function test_currencies_endpoint_is_read_only(): void
    {
        $owner = $this->owner();
        DB::table('exchange_rate_settings')->insert([
            'base_currency' => 'north',
            'rate_percent' => 380,
            'is_active' => true,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        Sanctum::actingAs($owner);

        $data = $this->getJson(self::BASE . '/currencies')
            ->assertOk()->json('data');

        $this->assertSame(3.8, round($data['north_to_south'], 4));
        $this->assertCount(2, $data['currencies']);
    }

    // ── Roles + isolation ────────────────────────────────────────

    public function test_distributor_collects_and_pays_via_dist_aliases(): void
    {
        $owner = $this->owner();
        $distUser = $this->person('771234010');
        $this->makeAgent($owner, $distUser, 'distributor');
        $pos = $this->makePos($owner);
        Sanctum::actingAs($distUser);

        $debtId = $this->postJson(self::BASE . '/debts', [
            'party_type' => 'pos',
            'party_id' => $pos->id,
            'amount_due' => 2000,
        ])->assertCreated()->json('data.id');

        $this->postJson(self::BASE . "/dist/debts/{$debtId}/pay", [
            'amount' => 2000,
        ])->assertOk()->assertJsonPath('data.debt.status', 'paid');

        $this->getJson(self::BASE . '/dist/collections')
            ->assertOk()->assertJsonCount(1, 'data.data');
    }

    public function test_pos_agent_sees_only_own_collections(): void
    {
        $owner = $this->owner();
        $posUser = $this->person('771234011');
        $posAgent = $this->makeAgent($owner, $posUser, 'pos');
        $pos = $this->makePos($owner, $posAgent);

        AccCollection::create([
            'network_owner_id' => $owner->id,
            'party_type' => 'pos',
            'party_id' => $pos->id,
            'party_name' => $pos->name,
            'amount' => 900,
            'currency' => 'north',
            'exchange_rate' => 1,
            'base_amount' => 900,
            'cash_box_id' => $this->box($owner, 'ر')->id,
        ]);

        Sanctum::actingAs($posUser);
        $this->getJson(self::BASE . '/pos/collections-received')
            ->assertOk()
            ->assertJsonCount(1, 'data.data')
            ->assertJsonPath('pos.id', $pos->id);

        // POS roles can't reach the money management surface.
        $this->getJson(self::BASE . '/collections')->assertForbidden();
        $this->getJson(self::BASE . '/cash-boxes')->assertForbidden();
    }

    public function test_tenant_isolation(): void
    {
        $ownerA = $this->owner('770000020');
        $ownerB = $this->owner('770000021');
        $posA = $this->makePos($ownerA);

        Sanctum::actingAs($ownerB);
        // B cannot collect on A's POS point — it doesn't exist in B's tenant.
        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos',
            'party_id' => $posA->id,
            'amount' => 100,
        ])->assertUnprocessable();

        $this->getJson(self::BASE . '/collections')->assertOk()
            ->assertJsonCount(0, 'data.data');
    }
}
