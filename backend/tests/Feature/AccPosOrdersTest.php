<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccJournalEntry;
use App\Models\AccPointsLedger;
use App\Models\AccPosOrder;
use App\Models\AccPosPoint;
use App\Models\AccProfitLedger;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-04 — the POS order cycle over the real HTTP stack:
 * request (pos agent) → approve/reject (owner/admin/distributor)
 * with stock-out + points + profit + a balanced journal entry in
 * ONE atomic transaction.
 *
 * Self-contained like the other acc tests. Because ACC-02's stock
 * tables have not landed yet, this suite builds minimal
 * PLAN-§2.1-shaped acc_card_categories/acc_stock/
 * acc_stock_movements schema — the production code writes to them
 * through Schema::hasTable hooks, so the same binary path runs in
 * the test.
 */
class AccPosOrdersTest extends TestCase
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
        if (! Schema::hasTable('acc_pos_orders')) {
            foreach (
                glob(database_path('migrations/2026_10_27_0400*_create_acc_*.php')) ?: []
                as $file
            ) {
                (require $file)->up();
            }
        }

        // ACC-02 stand-in schema (PLAN §2.1 columns) — exercises the
        // stock hook the same way the real migrations will.
        if (! Schema::hasTable('acc_card_categories')) {
            Schema::create('acc_card_categories', function (Blueprint $t) {
                $t->id();
                $t->foreignId('network_owner_id');
                $t->string('name');
                $t->decimal('sell_price', 15, 2)->default(0);
                $t->decimal('cost_price', 15, 2)->default(0);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('acc_stock')) {
            Schema::create('acc_stock', function (Blueprint $t) {
                $t->id();
                $t->foreignId('network_owner_id');
                $t->unsignedBigInteger('category_id');
                $t->decimal('qty', 15, 2)->default(0);
                $t->decimal('avg_cost', 15, 2)->default(0);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('acc_stock_movements')) {
            Schema::create('acc_stock_movements', function (Blueprint $t) {
                $t->id();
                $t->foreignId('network_owner_id');
                $t->unsignedBigInteger('category_id');
                $t->string('type', 30);
                $t->decimal('qty', 15, 2);
                $t->decimal('unit_cost', 15, 2)->default(0);
                $t->string('ref_type', 40)->nullable();
                $t->unsignedBigInteger('ref_id')->nullable();
                $t->unsignedBigInteger('agent_id')->nullable();
                $t->string('note')->nullable();
                $t->timestamp('created_at')->useCurrent();
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

    private function makeCategory(User $owner, float $sell, float $cost): int
    {
        return (int) DB::table('acc_card_categories')->insertGetId([
            'network_owner_id' => $owner->id,
            'name' => 'فئة ' . $sell,
            'sell_price' => $sell,
            'cost_price' => $cost,
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

    /** A pos agent bound to a funded point, plus the order payload. */
    private function posFixture(User $owner): array
    {
        $user = $this->person('771234001');
        $agent = $this->makeAgent($owner, $user, 'pos');
        $pos = $this->makePos($owner, $agent, ['points_balance' => 10000]);

        return [$user, $agent, $pos];
    }

    // ── Request (POS surface) ────────────────────────────────────

    public function test_pos_agent_submits_order_for_own_point(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 600);

        Sanctum::actingAs($posUser);
        $res = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [
                ['category_id' => $catId, 'qty' => 3],
                ['name' => 'حزمة خاصة', 'qty' => 2, 'unit_price' => 500, 'unit_cost' => 300],
            ],
            'points_total' => 4000,
            'note' => 'طلب أسبوعي',
        ]);

        $res->assertCreated()
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.pos_id', $pos->id)
            ->assertJsonPath('data.points_total', 4000)
            ->assertJsonPath('data.total_amount', 4000);

        $order = AccPosOrder::sole();
        $this->assertMatchesRegularExpression('/^PO-\d{8}-\d{6}$/', $order->order_no);
        $this->assertSame(2, $order->items()->count());
        // Server-side catalog pricing won over the absent unit_price.
        $catItem = $order->items()->where('category_id', $catId)->sole();
        $this->assertSame(1000.0, (float) $catItem->unit_price);
        $this->assertSame(600.0, (float) $catItem->unit_cost);
        $this->assertSame(3000.0, (float) $catItem->line_total);
    }

    public function test_order_create_is_idempotent_by_key(): void
    {
        $owner = $this->owner();
        [$posUser, , ] = $this->posFixture($owner);
        Sanctum::actingAs($posUser);

        $payload = [
            'items' => [['name' => 'حزمة', 'qty' => 1, 'unit_price' => 100]],
            'idempotency_key' => 'pos-req-001',
        ];
        $first = $this->postJson(self::BASE . '/pos/orders', $payload)->assertCreated();
        $second = $this->postJson(self::BASE . '/pos/orders', $payload)->assertCreated();

        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $this->assertSame(1, AccPosOrder::count());
    }

    public function test_pos_cannot_order_for_another_agents_point(): void
    {
        $owner = $this->owner();
        [$posUser] = $this->posFixture($owner);
        $otherAgent = $this->makeAgent($owner, $this->person('771234002'), 'pos');
        $otherPos = $this->makePos($owner, $otherAgent);

        Sanctum::actingAs($posUser);
        // The POS surface pins the order to the caller's own point —
        // the other point's orders stay invisible.
        $this->getJson(self::BASE . '/pos/orders')
            ->assertOk()->assertJsonCount(0, 'data.data');

        // Desk route still enforces ownership for a pos role.
        $res = $this->postJson(self::BASE . '/pos-orders', [
            'pos_id' => $otherPos->id,
            'items' => [['name' => 'x', 'qty' => 1, 'unit_price' => 10]],
        ]);
        $res->assertForbidden(); // pos role lacks pos-orders.decide
    }

    // ── Approve: the atomic cycle ────────────────────────────────

    public function test_approve_posts_stock_points_profit_and_journal_atomically(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);
        $dist = $this->makeAgent($owner, $this->person('771234003'), 'distributor', [
            'commission_mode' => 'percent', 'commission_value' => 10,
        ]);
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($posUser);
        $orderId = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [['category_id' => $catId, 'qty' => 4]],
            'points_total' => 4000,
            'distributor_id' => $dist->id,
        ])->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/approve")
            ->assertOk()
            ->assertJsonPath('data.status', 'approved');

        // Stock: 10 − 4 = 6, plus an order_fill movement.
        $this->assertSame(6.0, $this->stockQty($catId));
        $movement = DB::table('acc_stock_movements')->sole();
        $this->assertSame('order_fill', $movement->type);
        $this->assertSame(-4.0, (float) $movement->qty);
        $this->assertSame($orderId, (int) $movement->ref_id);

        // Points: 10000 − 4000 = 6000, plus ledger row.
        $this->assertSame(6000.0, (float) $pos->fresh()->points_balance);
        $ledger = AccPointsLedger::sole();
        $this->assertSame('order_purchase', $ledger->reason);
        $this->assertSame(-4000.0, (float) $ledger->delta);
        $this->assertSame(6000.0, (float) $ledger->balance_after);

        // Distributor commission: 10% of 4000 = 400.
        $profit = AccProfitLedger::sole();
        $this->assertSame('distributor', $profit->party_type);
        $this->assertSame($dist->id, $profit->party_id);
        $this->assertSame('sale_commission', $profit->reason);
        $this->assertSame(400.0, (float) $profit->delta);

        // Journal: one balanced pos_sale entry.
        $entry = AccJournalEntry::sole();
        $this->assertSame('pos_sale', $entry->doc_type);
        $this->assertSame($orderId, $entry->doc_ref_id);
        $this->assertSame('pos-order-' . $orderId . '-approve', $entry->idempotency_key);
        $lines = $entry->lines;
        $this->assertEquals(
            (float) $lines->sum('debit'),
            (float) $lines->sum('credit')
        );
        // covered-by-points 4000 + COGS 2400 + commission 400 = 6800
        $this->assertEquals(6800.0, (float) $lines->sum('debit'));

        $order = AccPosOrder::sole();
        $this->assertSame('approved', $order->status);
        $this->assertSame($owner->id, $order->approved_by);
        $this->assertNotNull($order->approved_at);
    }

    public function test_approve_is_replayable_without_double_posting(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);
        $catId = $this->makeCategory($owner, 500, 300);
        $this->stock($owner, $catId, 5);

        Sanctum::actingAs($posUser);
        $orderId = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [['category_id' => $catId, 'qty' => 2]],
            'points_total' => 1000,
        ])->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/approve")->assertOk();
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/approve")
            ->assertOk()->assertJsonPath('data.status', 'approved');

        // Nothing was applied twice.
        $this->assertSame(3.0, $this->stockQty($catId));
        $this->assertSame(9000.0, (float) $pos->fresh()->points_balance);
        $this->assertSame(1, AccPointsLedger::count());
        $this->assertSame(1, AccJournalEntry::count());
        $this->assertSame(1, DB::table('acc_stock_movements')->count());
    }

    public function test_insufficient_points_rolls_back_everything(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);
        $pos->update(['points_balance' => 100]); // less than the order needs
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 10);

        Sanctum::actingAs($posUser);
        $orderId = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [['category_id' => $catId, 'qty' => 4]],
            'points_total' => 4000,
        ])->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/approve")
            ->assertUnprocessable();

        // Full rollback: pending order, untouched stock/points,
        // zero ledger + journal rows.
        $this->assertSame('pending', AccPosOrder::sole()->status);
        $this->assertSame(10.0, $this->stockQty($catId));
        $this->assertSame(100.0, (float) $pos->fresh()->points_balance);
        $this->assertSame(0, DB::table('acc_stock_movements')->count());
        $this->assertSame(0, AccPointsLedger::count());
        $this->assertSame(0, AccProfitLedger::count());
        $this->assertSame(0, AccJournalEntry::count());
    }

    public function test_insufficient_stock_rolls_back_everything(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);
        $catId = $this->makeCategory($owner, 1000, 600);
        $this->stock($owner, $catId, 1); // not enough for qty 4

        Sanctum::actingAs($posUser);
        $orderId = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [['category_id' => $catId, 'qty' => 4]],
            'points_total' => 4000,
        ])->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/approve")
            ->assertUnprocessable();

        $this->assertSame('pending', AccPosOrder::sole()->status);
        $this->assertSame(1.0, $this->stockQty($catId));
        $this->assertSame(10000.0, (float) $pos->fresh()->points_balance);
        $this->assertSame(0, AccPointsLedger::count());
        $this->assertSame(0, AccJournalEntry::count());
    }

    // ── Reject + decision rules ──────────────────────────────────

    public function test_reject_blocks_approval_and_posts_nothing(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);

        Sanctum::actingAs($posUser);
        $orderId = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [['name' => 'حزمة', 'qty' => 1, 'unit_price' => 100]],
            'points_total' => 100,
        ])->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/reject", [
            'reason' => 'رصيد غير مستحق',
        ])->assertOk()->assertJsonPath('data.status', 'rejected');

        $this->postJson(self::BASE . "/pos-orders/{$orderId}/approve")
            ->assertConflict();

        $this->assertSame('rejected', AccPosOrder::sole()->status);
        $this->assertSame('رصيد غير مستحق', AccPosOrder::sole()->reject_reason);
        $this->assertSame(10000.0, (float) $pos->fresh()->points_balance);
        $this->assertSame(0, AccPointsLedger::count());
        $this->assertSame(0, AccJournalEntry::count());

        // Re-rejecting replays cleanly.
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/reject")
            ->assertOk()->assertJsonPath('data.status', 'rejected');
    }

    public function test_approved_order_cannot_be_rejected(): void
    {
        $owner = $this->owner();
        [$posUser] = $this->posFixture($owner);

        Sanctum::actingAs($posUser);
        $orderId = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [['name' => 'حزمة', 'qty' => 1, 'unit_price' => 100]],
            'points_total' => 100,
        ])->assertCreated()->json('data.id');

        Sanctum::actingAs($owner);
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/approve")->assertOk();
        $this->postJson(self::BASE . "/pos-orders/{$orderId}/reject")->assertConflict();
        $this->assertSame('approved', AccPosOrder::sole()->status);
    }

    // ── Roles + distributor surface ──────────────────────────────

    public function test_distributor_reads_and_decides_via_dist_alias(): void
    {
        $owner = $this->owner();
        [$posUser, , $pos] = $this->posFixture($owner);
        $distUser = $this->person('771234004');
        $this->makeAgent($owner, $distUser, 'distributor');

        Sanctum::actingAs($posUser);
        $orderId = $this->postJson(self::BASE . '/pos/orders', [
            'items' => [['name' => 'حزمة', 'qty' => 1, 'unit_price' => 200]],
            'points_total' => 200,
        ])->assertCreated()->json('data.id');

        Sanctum::actingAs($distUser);
        $this->getJson(self::BASE . '/dist/pos-orders')
            ->assertOk()->assertJsonCount(1, 'data.data');
        $this->postJson(self::BASE . "/dist/pos-orders/{$orderId}/approve")
            ->assertOk()->assertJsonPath('data.status', 'approved');

        // The deciding distributor is stamped on the order.
        $this->assertNotNull(AccPosOrder::sole()->distributor_id);
        $this->assertSame(9800.0, (float) $pos->fresh()->points_balance);
    }

    public function test_management_list_filters_and_includes_items(): void
    {
        $owner = $this->owner();
        [, , $pos] = $this->posFixture($owner);
        $order = AccPosOrder::create([
            'network_owner_id' => $owner->id,
            'order_no' => 'PO-20990101-000001',
            'pos_id' => $pos->id,
            'status' => 'pending',
            'total_amount' => 50, 'points_total' => 50,
        ]);
        $order->items()->create([
            'category_name' => 'حزمة', 'qty' => 1,
            'unit_price' => 50, 'line_total' => 50,
        ]);

        Sanctum::actingAs($owner);
        $this->getJson(self::BASE . '/pos-orders?status=pending')
            ->assertOk()
            ->assertJsonCount(1, 'data.data')
            ->assertJsonPath('data.data.0.order_no', 'PO-20990101-000001')
            ->assertJsonPath('data.data.0.pos_name', 'بقالة النور')
            ->assertJsonCount(1, 'data.data.0.items');
        $this->getJson(self::BASE . '/pos-orders?status=approved')
            ->assertOk()->assertJsonCount(0, 'data.data');
    }

    // ── Isolation ────────────────────────────────────────────────

    public function test_tenant_isolation(): void
    {
        $ownerA = $this->owner('770000001');
        $ownerB = $this->owner('770000002');
        [, , $posA] = $this->posFixture($ownerA);
        $orderA = AccPosOrder::create([
            'network_owner_id' => $ownerA->id,
            'order_no' => 'PO-20990101-000009',
            'pos_id' => $posA->id,
            'status' => 'pending',
            'total_amount' => 10, 'points_total' => 10,
        ]);

        Sanctum::actingAs($ownerB);
        $this->getJson(self::BASE . '/pos-orders')->assertOk()
            ->assertJsonCount(0, 'data.data');
        $this->postJson(self::BASE . "/pos-orders/{$orderA->id}/approve")
            ->assertNotFound();
        $this->postJson(self::BASE . "/pos-orders/{$orderA->id}/reject")
            ->assertNotFound();
        $this->assertSame('pending', $orderA->fresh()->status);
    }
}
