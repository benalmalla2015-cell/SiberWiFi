<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccCashBox;
use App\Models\AccDebt;
use App\Models\AccJournalEntry;
use App\Models\AccPointsLedger;
use App\Models\AccPosOrder;
use App\Models\AccPosPoint;
use App\Models\AccProfitLedger;
use App\Models\AccSale;
use App\Models\AccWebhookEvent;
use App\Models\AccWithdrawal;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-10 — شرائح الخصم + الأرصدة/السحوبات + قوالب إشعارات واتساب
 * over the real HTTP stack:
 *
 *   - acc_discount_tiers CRUD + /discount-tiers/match preview
 *   - direct_percent tier discounts a dist sale atomically
 *   - points / profit_balance / commission tiers credit their
 *     ledgers inside the same transaction
 *   - pos order approval applies the tier and caps the prepayment
 *   - acc_webhook_events CRUD + render preview + notifications
 *     appended to sale/collection responses + due-debt reminders
 *   - GET /balances party read model
 *   - acc_withdrawals decision flow stays intact (اعتماد)
 *
 * Self-contained like the other acc suites: it builds the core
 * schema plus every sprint's create_acc_* migrations and the
 * ACC-10 additive-column migration.
 */
class AccDiscountsWebhooksTest extends TestCase
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

        // ACC-10 — tiers + webhook templates, then the additive
        // discount_amount columns on the document tables.
        foreach (
            glob(database_path('migrations/2026_10_29_1000*_create_acc_*.php')) ?: []
            as $file
        ) {
            (require $file)->up();
        }
        if (Schema::hasTable('acc_sales')
            && ! Schema::hasColumn('acc_sales', 'discount_amount')) {
            (require database_path(
                'migrations/2026_10_29_100003_add_discount_amount_to_acc_docs.php'
            ))->up();
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
            'phone' => '777123456',
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

    private function distFixture(User $owner, array $agentOver = []): array
    {
        $user = $this->person('771234500');
        $agent = $this->makeAgent($owner, $user, 'distributor', array_merge([
            'cash_allowed' => true,
            'credit_allowed' => true,
        ], $agentOver));
        $pos = $this->makePos($owner);

        return [$user, $agent, $pos];
    }

    private function makeTier(User $owner, string $mode, string $basis, array $over = []): int
    {
        return (int) DB::table('acc_discount_tiers')->insertGetId(array_merge([
            'network_owner_id' => $owner->id,
            'mode' => $mode,
            'basis' => $basis,
            'min' => 1,
            'max' => null,
            'reward_value' => 10,
            'reward_unit' => 'percent',
            'sort_order' => 0,
            'is_active' => true,
            'created_at' => now(), 'updated_at' => now(),
        ], $over));
    }

    private function salePayload(int $posId, int $catId, int $qty, string $kind, array $extra = []): array
    {
        return array_merge([
            'pos_id' => $posId,
            'items' => [['category_id' => $catId, 'qty' => $qty]],
            'payment_kind' => $kind,
        ], $extra);
    }

    // ── Tiers CRUD + match preview ───────────────────────────────

    public function test_tier_crud_and_match_preview(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $res = $this->postJson(self::BASE . '/discount-tiers', [
            'mode' => 'direct_percent', 'basis' => 'qty',
            'min' => 10, 'max' => 49, 'reward_value' => 5,
            'reward_unit' => 'percent',
        ])->assertCreated()->assertJsonPath('data.mode', 'direct_percent');
        $id = $res->json('data.id');

        $this->postJson(self::BASE . '/discount-tiers', [
            'mode' => 'direct_percent', 'basis' => 'qty',
            'min' => 50, 'max' => null, 'reward_value' => 10,
            'reward_unit' => 'percent',
        ])->assertCreated();

        // Deeper bracket (min=50) wins for qty=60.
        $match = $this->postJson(self::BASE . '/discount-tiers/match', [
            'qty' => 60, 'amount' => 60000,
        ])->assertOk();
        $this->assertCount(1, $match->json('data'));
        $this->assertSame(10.0, (float) $match->json('data.0.reward_value'));
        $this->assertSame(6000.0, (float) $match->json('data.0.reward'));

        // Update + delete round-trip.
        $this->putJson(self::BASE . "/discount-tiers/$id", [
            'reward_value' => 7,
        ])->assertOk()->assertJsonPath('data.reward_value', 7);
        $this->deleteJson(self::BASE . "/discount-tiers/$id")->assertOk();
        $this->assertSame(1, DB::table('acc_discount_tiers')->count());

        // Tenant isolation: another owner sees nothing.
        $other = $this->owner('770000009');
        Sanctum::actingAs($other);
        $this->getJson(self::BASE . '/discount-tiers')
            ->assertOk()->assertJsonCount(0, 'data');
    }

    // ── direct_percent on a dist sale ────────────────────────────

    public function test_direct_percent_tier_discounts_dist_sale(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 20);

        // 10% off once the document reaches 5 cards.
        $this->makeTier($owner, 'direct_percent', 'qty', [
            'min' => 5, 'reward_value' => 10, 'reward_unit' => 'percent',
        ]);

        Sanctum::actingAs($distUser);
        $res = $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 10, 'cash')
        );

        // Gross 10000 − 10% = 9000 payable; the discount snapshots
        // on the document and the journal posts the net value.
        $res->assertCreated()
            ->assertJsonPath('data.total_amount', 9000)
            ->assertJsonPath('data.discount_amount', 1000)
            ->assertJsonPath('data.paid_amount', 9000);

        $sale = AccSale::sole();
        $this->assertSame(9000.0, (float) $sale->total_amount);
        $this->assertSame(1000.0, (float) $sale->discount_amount);

        $box = AccCashBox::sole();
        $this->assertSame(9000.0, (float) $box->balance);

        $lines = AccJournalEntry::sole()->lines;
        $this->assertEquals((float) $lines->sum('debit'), (float) $lines->sum('credit'));
        $revenue = $lines->firstWhere('account_code', '4000');
        $this->assertSame(9000.0, (float) $revenue->credit);
    }

    public function test_tier_below_min_and_inactive_do_not_apply(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 20);

        $this->makeTier($owner, 'direct_percent', 'qty', [
            'min' => 5, 'reward_value' => 10,
        ]);
        // An inactive 20% tier must never fire.
        $this->makeTier($owner, 'direct_percent', 'amount', [
            'min' => 0, 'reward_value' => 20, 'is_active' => false,
        ]);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 2, 'cash')
        )->assertCreated()
            ->assertJsonPath('data.total_amount', 2000)
            ->assertJsonPath('data.discount_amount', 0);

        $this->assertSame(0.0, (float) AccSale::sole()->discount_amount);
    }

    // ── points / profit / commission tiers ───────────────────────

    public function test_points_and_profit_tiers_credit_the_pos(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 20);

        $this->makeTier($owner, 'points', 'amount', [
            'min' => 5000, 'reward_value' => 200, 'reward_unit' => 'fixed',
        ]);
        $this->makeTier($owner, 'profit_balance', 'amount', [
            'min' => 5000, 'reward_value' => 5, 'reward_unit' => 'percent',
        ]);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 10, 'cash')
        )->assertCreated();

        $pos->refresh();
        $this->assertSame(200.0, (float) $pos->points_balance);
        $this->assertSame(500.0, (float) $pos->profit_balance); // 5% × 10000

        $pointsRow = AccPointsLedger::where('reason', 'bonus')->sole();
        $this->assertSame(200.0, (float) $pointsRow->delta);
        $this->assertSame('acc_sales', $pointsRow->ref_type);

        $profitRow = AccProfitLedger::where('party_type', 'pos')->sole();
        $this->assertSame(500.0, (float) $profitRow->delta);
        $this->assertSame('adjustment', $profitRow->reason);
    }

    public function test_commission_tier_stacks_on_agent_commission(): void
    {
        $owner = $this->owner();
        [$distUser, $agent, $pos] = $this->distFixture($owner, [
            'commission_mode' => 'percent', 'commission_value' => 10,
        ]);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 20);

        // +500 flat commission once the sale reaches 5000.
        $this->makeTier($owner, 'commission', 'amount', [
            'min' => 5000, 'reward_value' => 500, 'reward_unit' => 'fixed',
        ]);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 10, 'cash')
        )->assertCreated();

        // 10% × 10000 + 500 tier = 1500.
        $sale = AccSale::sole();
        $this->assertSame(1500.0, (float) $sale->commission_amount);

        $profit = AccProfitLedger::where('party_type', 'distributor')->sole();
        $this->assertSame($agent->id, $profit->party_id);
        $this->assertSame(1500.0, (float) $profit->delta);
    }

    // ── POS order approval ───────────────────────────────────────

    public function test_order_approval_applies_tier_and_caps_prepayment(): void
    {
        $owner = $this->owner();
        $posAgent = $this->makeAgent($owner, $this->person('771234777'), 'pos');
        $pos = $this->makePos($owner, $posAgent, ['points_balance' => 1000]);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        // 10% off orders of 500+.
        $this->makeTier($owner, 'direct_percent', 'amount', [
            'min' => 500, 'reward_value' => 10,
        ]);

        Sanctum::actingAs($owner);
        $created = $this->postJson(self::BASE . '/pos-orders', [
            'pos_id' => $pos->id,
            'points_total' => 1000,
            'items' => [['category_id' => $catId, 'qty' => 1]],
        ])->assertCreated();

        $orderId = $created->json('data.id');
        $res = $this->postJson(self::BASE . "/pos-orders/$orderId/approve")->assertOk();

        // Discounted value 900 — the POS spends 900, not 1000.
        $this->assertSame(900.0, (float) $res->json('data.points_total'));
        $this->assertSame(100.0, (float) $res->json('data.discount_amount'));

        $pos->refresh();
        $this->assertSame(100.0, (float) $pos->points_balance);

        $order = AccPosOrder::sole();
        $this->assertSame(100.0, (float) $order->discount_amount);
        $this->assertSame(900.0, (float) $order->points_total);

        $lines = AccJournalEntry::sole()->lines;
        $this->assertEquals((float) $lines->sum('debit'), (float) $lines->sum('credit'));
        $revenue = $lines->firstWhere('account_code', '4000');
        $this->assertSame(900.0, (float) $revenue->credit);
    }

    // ── WhatsApp templates + dispatch ────────────────────────────

    public function test_webhook_crud_preview_and_sale_notification(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($owner);
        $res = $this->postJson(self::BASE . '/webhook-events', [
            'event' => 'sale.created',
            'template_body' => 'بيع جديد لـ {pos_name} رقم {sale_no} بقيمة {total} {currency}',
        ])->assertCreated()->assertJsonPath('data.event', 'sale.created');
        $eventId = $res->json('data.id');
        $this->assertSame(['pos_name', 'sale_no', 'total', 'currency'],
            $res->json('data.placeholders'));

        // Preview renders the placeholders.
        $preview = $this->postJson(
            self::BASE . "/webhook-events/$eventId/preview",
            ['vars' => ['pos_name' => 'متجر', 'sale_no' => 'SA-1', 'total' => 5, 'currency' => 'ر']]
        )->assertOk();
        $this->assertSame('بيع جديد لـ متجر رقم SA-1 بقيمة 5 ر',
            $preview->json('data.body'));

        // A sale now returns a rendered WhatsApp notification.
        Sanctum::actingAs($distUser);
        $sale = $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 2, 'cash')
        )->assertCreated();

        $note = collect($sale->json('notifications'))->first();
        $this->assertSame('sale.created', $note['event']);
        $this->assertSame('whatsapp', $note['channel']);
        $this->assertStringContainsString('بقالة النور', $note['body']);
        $this->assertStringContainsString('2000', $note['body']);
        $this->assertStringStartsWith('https://wa.me/967777123456', $note['wa_url']);

        // Every dispatch is audited.
        $audit = DB::table('acc_audit_log')
            ->where('action', 'webhook.dispatch')->sole();
        $this->assertSame('acc_webhook_events', $audit->entity);
        $this->assertSame($eventId, (int) $audit->entity_id);
    }

    public function test_collection_notification_and_debt_due_reminder(): void
    {
        $owner = $this->owner();
        [, , $pos] = $this->distFixture($owner);

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . '/webhook-events', [
            'event' => 'collection.created',
            'template_body' => 'استلمنا {amount} {currency} من {party_name}',
        ])->assertCreated();
        $this->postJson(self::BASE . '/webhook-events', [
            'event' => 'debt.due',
            'template_body' => 'تذكير: على {party_name} مبلغ {remaining} مستحق بتاريخ {due_date}',
        ])->assertCreated();

        // Collection → rendered notification to the POS phone.
        $res = $this->postJson(self::BASE . '/collections', [
            'party_type' => 'pos', 'party_id' => $pos->id,
            'party_name' => $pos->name, 'phone' => $pos->phone,
            'amount' => 750,
        ])->assertCreated();

        $note = collect($res->json('notifications'))->first();
        $this->assertSame('collection.created', $note['event']);
        $this->assertStringContainsString('750', $note['body']);
        $this->assertStringStartsWith('https://wa.me/', $note['wa_url']);

        // An overdue debt surfaces on /notifications/debt-due.
        AccDebt::create([
            'network_owner_id' => $owner->id,
            'party_type' => 'pos', 'party_id' => $pos->id,
            'party_name' => $pos->name, 'phone' => $pos->phone,
            'amount_due' => 500, 'amount_paid' => 100,
            'currency' => 'north', 'base_due' => 500, 'base_paid' => 100,
            'status' => 'partial',
            'due_date' => now()->subDays(2)->toDateString(),
        ]);

        $due = $this->getJson(self::BASE . '/notifications/debt-due')
            ->assertOk()->assertJsonCount(1, 'data');
        $row = $due->json('data.0');
        $this->assertSame(400.0, (float) $row['remaining']);
        $this->assertStringContainsString('400', $row['body']);
        $this->assertStringContainsString('بقالة النور', $row['body']);
        $this->assertNotNull($row['wa_url']);
    }

    public function test_inactive_template_dispatches_nothing(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        AccWebhookEvent::create([
            'network_owner_id' => $owner->id,
            'event' => 'sale.created',
            'template_body' => 'x',
            'is_active' => false,
        ]);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 1, 'cash')
        )->assertCreated()->assertJsonCount(0, 'notifications');
    }

    // ── Balances + withdrawals review ────────────────────────────

    public function test_balances_lists_parties_with_names(): void
    {
        $owner = $this->owner();
        [$distUser, , $pos] = $this->distFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 0);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($distUser);
        $this->postJson(
            self::BASE . '/dist/sale',
            $this->salePayload($pos->id, $catId, 3, 'credit')
        )->assertCreated();

        Sanctum::actingAs($owner);
        $res = $this->getJson(self::BASE . '/balances?party=pos')->assertOk();
        $row = collect($res->json('data'))->sole('party_id', $pos->id);
        $this->assertSame('pos', $row['party_type']);
        $this->assertSame('بقالة النور', $row['party_name']);
        $this->assertSame(3000.0, (float) $row['balance']);

        // Distributor cannot read the management balances surface.
        Sanctum::actingAs($distUser);
        $this->getJson(self::BASE . '/balances')->assertForbidden();
    }

    public function test_withdrawal_decision_flow_stays_atomic(): void
    {
        $owner = $this->owner();
        $posUser = $this->person('771234888');
        $posAgent = $this->makeAgent($owner, $posUser, 'pos');
        $pos = $this->makePos($owner, $posAgent, ['profit_balance' => 2000]);

        // The payout box must actually hold the money.
        AccCashBox::create([
            'network_owner_id' => $owner->id,
            'name' => 'الصندوق الرئيسي', 'currency' => 'north',
            'balance' => 5000, 'is_default' => true, 'is_active' => true,
        ]);

        // POS requests 1500 of its profit balance.
        Sanctum::actingAs($posUser);
        $res = $this->postJson(self::BASE . '/pos/withdrawals', [
            'amount' => 1500, 'receiver_name' => 'أمين الصندوق',
        ])->assertCreated();
        $id = $res->json('data.id');

        $pos->refresh();
        $this->assertSame(500.0, (float) $pos->profit_balance); // held

        // Owner approves then pays out of the default box.
        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/withdrawals/$id/approve")->assertOk();
        $this->postJson(self::BASE . "/withdrawals/$id/paid", [
            'receipt_no' => 'R-1',
        ])->assertOk();

        $w = AccWithdrawal::sole();
        $this->assertSame('paid', $w->status);
        $this->assertNotNull($w->journal_entry_id);
        $this->assertSame(3500.0, (float) AccCashBox::sole()->balance);

        // The withdrawal entry is balanced.
        $lines = AccJournalEntry::find($w->journal_entry_id)->lines;
        $this->assertEquals((float) $lines->sum('debit'), (float) $lines->sum('credit'));
    }
}
