<?php

namespace Tests\Feature;

use App\Models\AccCardCategory;
use App\Models\AccCardImport;
use App\Models\AccDamaged;
use App\Models\AccJournalEntry;
use App\Models\AccPurchase;
use App\Models\AccReturn;
use App\Models\AccStock;
use App\Models\AccStockMovement;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-02 — inventory & card categories (PLAN §2.1): categories CRUD,
 * purchases/returns/damaged posting atomically into acc_stock +
 * journal, and the read-only MikroTik router-card auto-sync.
 *
 * Self-contained like the sibling suites: builds a minimal
 * users/networks/card_categories/cards schema plus the acc_*
 * migrations it needs.
 */
class AccInventoryTest extends TestCase
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
        if (! Schema::hasTable('card_categories')) {
            Schema::create('card_categories', function (Blueprint $t) {
                $t->id();
                $t->foreignId('network_id');
                $t->string('name');
                $t->decimal('price', 12, 2)->default(0);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('cards')) {
            Schema::create('cards', function (Blueprint $t) {
                $t->id();
                $t->foreignId('network_id');
                $t->foreignId('category_id');
                $t->string('card_number');
                $t->string('status', 12)->default('available');
                $t->string('source', 20)->default('platform');
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('acc_card_categories')) {
            foreach ([
                ...glob(database_path('migrations/2026_10_26_0100*_create_acc_*.php')) ?: [],
                database_path('migrations/2026_10_27_020001_create_acc_agents_table.php'),
                ...glob(database_path('migrations/2026_10_27_0300*_create_acc_*.php')) ?: [],
            ] as $file) {
                (require $file)->up();
            }
        }
    }

    private function owner(string $phone = '770000001'): User
    {
        return User::factory()->create([
            'type' => 'network_owner',
            'phone' => $phone,
            'is_active' => true,
        ]);
    }

    private function networkFor(User $owner): int
    {
        return (int) DB::table('networks')->insertGetId(['user_id' => $owner->id]);
    }

    private function platformCategory(int $networkId, string $name, float $price): int
    {
        return (int) DB::table('card_categories')->insertGetId([
            'network_id' => $networkId,
            'name' => $name,
            'price' => $price,
        ]);
    }

    private function card(int $networkId, int $catId, string $status, string $source = 'mikrotik'): int
    {
        return (int) DB::table('cards')->insertGetId([
            'network_id' => $networkId,
            'category_id' => $catId,
            'card_number' => 'c' . uniqid(),
            'status' => $status,
            'source' => $source,
        ]);
    }

    private function makeCategory(User $owner, array $over = []): AccCardCategory
    {
        return AccCardCategory::create(array_merge([
            'network_owner_id' => $owner->id,
            'name' => 'باقة ساعة',
            'sell_price' => 200,
            'cost_price' => 100,
            'source_binding' => 'any',
            'is_active' => true,
        ], $over));
    }

    // ── Categories ───────────────────────────────────────────────

    public function test_categories_crud_with_stock_projection(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $res = $this->postJson(self::BASE . '/categories', [
            'name' => 'باقة يومية',
            'sell_price' => 500,
            'cost_price' => 300,
            'unit_label' => 'كرت',
            'source_binding' => 'mikrotik',
        ]);
        $res->assertCreated()
            ->assertJsonPath('data.name', 'باقة يومية');
        $this->assertSame(0.0, (float) $res->json('data.stock_qty'));

        $id = $res->json('data.id');

        $this->putJson(self::BASE . "/categories/{$id}", ['sell_price' => 600])
            ->assertOk();
        $this->assertSame(600.0, (float) $this->getJson(
            self::BASE . '/categories')->json('data.0.sell_price'));

        $this->getJson(self::BASE . '/categories')
            ->assertOk()->assertJsonCount(1, 'data');

        // Unused category deletes cleanly.
        $this->deleteJson(self::BASE . "/categories/{$id}")->assertOk();
        $this->assertSame(0, AccCardCategory::count());
    }

    public function test_category_with_movements_cannot_be_deleted(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $cat = $this->makeCategory($owner);

        $this->postJson(self::BASE . '/stock/adjust', [
            'category_id' => $cat->id, 'qty' => 10,
        ])->assertOk();

        $this->deleteJson(self::BASE . "/categories/{$cat->id}")
            ->assertUnprocessable();
        // But disabling it works.
        $this->putJson(self::BASE . "/categories/{$cat->id}", ['is_active' => false])
            ->assertOk()->assertJsonPath('data.is_active', false);
    }

    // ── Stock: adjust + movements ────────────────────────────────

    public function test_adjust_sets_absolute_balance_with_signed_delta(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $cat = $this->makeCategory($owner);

        $this->postJson(self::BASE . '/stock/adjust', [
            'category_id' => $cat->id, 'qty' => 50, 'note' => 'جرد افتتاحي',
        ])->assertOk();

        $this->assertSame(50.0, (float) AccStock::sole()->qty);
        $this->assertSame(50.0, (float) AccStockMovement::sole()->qty);
        $this->assertSame('adjust', AccStockMovement::sole()->type);

        // Adjust down records a negative delta.
        $this->postJson(self::BASE . '/stock/adjust', [
            'category_id' => $cat->id, 'qty' => 35,
        ])->assertOk();
        $this->assertSame(35.0, (float) AccStock::sole()->qty);
        $this->assertSame(-15.0, (float) AccStockMovement::latest('id')->first()->qty);

        // No-op and negative targets are rejected.
        $this->postJson(self::BASE . '/stock/adjust', [
            'category_id' => $cat->id, 'qty' => 35,
        ])->assertUnprocessable();
        $this->postJson(self::BASE . '/stock/adjust', [
            'category_id' => $cat->id, 'qty' => -5,
        ])->assertUnprocessable();
    }

    // ── Purchases ────────────────────────────────────────────────

    public function test_purchase_posts_stock_in_and_balanced_journal(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $cat = $this->makeCategory($owner);

        $res = $this->postJson(self::BASE . '/suppliers', ['name' => 'مورد الكروت']);
        $supplierId = $res->json('data.id');

        $res = $this->postJson(self::BASE . '/purchases', [
            'supplier_id' => $supplierId,
            'category_id' => $cat->id,
            'qty' => 100,
            'unit_price' => 80,
            'payment' => 'credit',
        ]);
        $res->assertCreated();
        $this->assertSame(8000.0, (float) $res->json('data.total'));

        $stock = AccStock::sole();
        $this->assertSame(100.0, (float) $stock->qty);
        $this->assertSame(80.0, (float) $stock->avg_cost);

        $mv = AccStockMovement::sole();
        $this->assertSame('in', $mv->type);
        $this->assertSame('acc_purchases', $mv->ref_type);
        $this->assertSame(AccPurchase::sole()->id, $mv->ref_id);

        $entry = AccJournalEntry::sole();
        $this->assertSame('purchase', $entry->doc_type);
        $this->assertEquals(
            (float) $entry->lines->sum('debit'),
            (float) $entry->lines->sum('credit')
        );
        // Credit purchase → supplier payable carries a party.
        $this->assertSame('2300', $entry->lines->firstWhere('credit', '>', 0)->account_code);
    }

    public function test_weighted_average_cost_across_purchases(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $cat = $this->makeCategory($owner);

        $this->postJson(self::BASE . '/purchases', [
            'category_id' => $cat->id, 'qty' => 10, 'unit_price' => 100,
        ])->assertCreated();
        $this->postJson(self::BASE . '/purchases', [
            'category_id' => $cat->id, 'qty' => 10, 'unit_price' => 200,
        ])->assertCreated();

        $stock = AccStock::sole();
        $this->assertSame(20.0, (float) $stock->qty);
        $this->assertSame(150.0, (float) $stock->avg_cost);
    }

    // ── Damaged ──────────────────────────────────────────────────

    public function test_damaged_posts_stock_out_and_journal(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $cat = $this->makeCategory($owner);

        $this->postJson(self::BASE . '/purchases', [
            'category_id' => $cat->id, 'qty' => 20, 'unit_price' => 50,
        ])->assertCreated();

        $this->postJson(self::BASE . '/damaged', [
            'category_id' => $cat->id, 'qty' => 5, 'reason' => 'كروت مبللة',
        ])->assertCreated();

        $this->assertSame(15.0, (float) AccStock::sole()->qty);
        $mv = AccStockMovement::latest('id')->first();
        $this->assertSame('damaged', $mv->type);
        $this->assertSame(-5.0, (float) $mv->qty);

        $entry = AccJournalEntry::latest('id')->first();
        $this->assertSame('damaged', $entry->doc_type);

        // Over-damaging beyond the balance is refused atomically.
        $this->postJson(self::BASE . '/damaged', [
            'category_id' => $cat->id, 'qty' => 100,
        ])->assertStatus(409);
        $this->assertSame(1, AccDamaged::count());
        $this->assertSame(15.0, (float) AccStock::sole()->qty);
    }

    // ── Returns ──────────────────────────────────────────────────

    public function test_sale_return_reenters_stock_and_journal(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $cat = $this->makeCategory($owner);

        $this->postJson(self::BASE . '/purchases', [
            'category_id' => $cat->id, 'qty' => 10, 'unit_price' => 40,
        ])->assertCreated();

        $this->postJson(self::BASE . '/returns', [
            'kind' => 'sale_return',
            'category_id' => $cat->id,
            'qty' => 3,
            'amount' => 600,
            'reason' => 'كروت معطلة',
        ])->assertCreated();

        $this->assertSame(13.0, (float) AccStock::sole()->qty);
        $mv = AccStockMovement::latest('id')->first();
        $this->assertSame('return', $mv->type);
        $this->assertSame(3.0, (float) $mv->qty);

        $entry = AccJournalEntry::latest('id')->first();
        $this->assertSame('return', $entry->doc_type);
        $this->assertEquals(
            (float) $entry->lines->sum('debit'),
            (float) $entry->lines->sum('credit')
        );
    }

    public function test_purchase_return_ships_stock_out(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $cat = $this->makeCategory($owner);

        $this->postJson(self::BASE . '/purchases', [
            'category_id' => $cat->id, 'qty' => 10, 'unit_price' => 40,
        ])->assertCreated();

        $this->postJson(self::BASE . '/returns', [
            'kind' => 'purchase_return',
            'category_id' => $cat->id,
            'qty' => 4,
            'amount' => 160,
        ])->assertCreated();

        $this->assertSame(6.0, (float) AccStock::sole()->qty);
        $this->assertSame(-4.0, (float) AccStockMovement::latest('id')->first()->qty);
        $this->assertSame(1, AccReturn::count());
    }

    // ── MikroTik router-card auto-sync ───────────────────────────

    public function test_router_cards_enter_stock_automatically(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $netId = $this->networkFor($owner);
        $platCat = $this->platformCategory($netId, 'فئة الراوتر', 300);

        $this->card($netId, $platCat, 'available');
        $this->card($netId, $platCat, 'available');
        $this->card($netId, $platCat, 'sold');
        // Platform-source cards must never be picked up.
        $this->card($netId, $platCat, 'available', 'platform');

        $res = $this->getJson(self::BASE . '/stock');
        $res->assertOk();

        // Auto-created acc category bound to the platform category.
        $cat = AccCardCategory::where('card_category_id', $platCat)->sole();
        $this->assertSame('فئة الراوتر', $cat->name);
        $this->assertSame('mikrotik', $cat->source_binding);
        $this->assertSame(300.0, (float) $cat->sell_price);

        // 3 in, 1 sold out → stock = 2.
        $stock = AccStock::where('category_id', $cat->id)->sole();
        $this->assertSame(2.0, (float) $stock->qty);
        $this->assertSame(4, AccStockMovement::count());
        $this->assertSame(1, AccCardImport::where('source', 'mikrotik')->count());
    }

    public function test_router_sync_is_idempotent_and_incremental(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $netId = $this->networkFor($owner);
        $platCat = $this->platformCategory($netId, 'باقة', 100);
        $this->card($netId, $platCat, 'available');

        $this->postJson(self::BASE . '/stock/sync')
            ->assertOk()->assertJsonPath('data.imported', 1);
        // Replay — nothing double-counts.
        $this->postJson(self::BASE . '/stock/sync')
            ->assertOk()->assertJsonPath('data.imported', 0);

        // A card generated later joins on the next read.
        $this->card($netId, $platCat, 'available');
        $this->getJson(self::BASE . '/stock')->assertOk();

        $cat = AccCardCategory::where('card_category_id', $platCat)->sole();
        $this->assertSame(2.0, (float) AccStock::where('category_id', $cat->id)->sole()->qty);
        $this->assertSame(2, AccStockMovement::where('type', 'in')->count());
    }

    public function test_router_sync_respects_bound_mikrotik_category(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $netId = $this->networkFor($owner);
        $platCat = $this->platformCategory($netId, 'منصة ٥٠٠', 500);

        // Owner pre-created a bound acc bucket — sync must use it,
        // not create a duplicate.
        $bound = $this->makeCategory($owner, [
            'name' => 'باقة ٥٠٠ مخصصة',
            'card_category_id' => $platCat,
        ]);
        $this->card($netId, $platCat, 'available');

        $this->getJson(self::BASE . '/stock')->assertOk();

        $this->assertSame(1, AccCardCategory::count());
        $this->assertSame(1.0, (float) AccStock::where('category_id', $bound->id)->sole()->qty);
    }

    // ── CSV import ───────────────────────────────────────────────

    public function test_csv_import_creates_categories_and_movements(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $res = $this->postJson(self::BASE . '/stock/import', [
            'csv' => "name,qty,unit_cost,sell_price\nباقة أ,10,50,100\nباقة ب,5,30,60\nسيئة,0,0,0",
        ]);
        $res->assertOk()->assertJsonPath('data.imported_count', 2)
            ->assertJsonPath('data.skipped_count', 1)
            ->assertJsonPath('data.status', 'partial');

        $this->assertSame(2, AccCardCategory::count());
        $this->assertSame(2, AccStockMovement::where('type', 'in')->count());
        $this->assertSame(1, AccCardImport::where('source', 'file')->count());
    }

    // ── Tenant isolation ─────────────────────────────────────────

    public function test_inventory_is_tenant_isolated(): void
    {
        $ownerA = $this->owner('770000001');
        $ownerB = $this->owner('770000002');
        $catA = $this->makeCategory($ownerA);
        $this->makeCategory($ownerB, ['name' => 'فئة ب']);

        Sanctum::actingAs($ownerA);
        $this->postJson(self::BASE . '/stock/adjust', [
            'category_id' => $catA->id, 'qty' => 9,
        ])->assertOk();

        Sanctum::actingAs($ownerB);
        $this->getJson(self::BASE . '/categories')
            ->assertOk()->assertJsonCount(1, 'data');
        $this->getJson(self::BASE . '/stock')
            ->assertOk()->assertJsonCount(0, 'data');

        // B cannot reach A's category/stock docs.
        $this->putJson(self::BASE . "/categories/{$catA->id}", ['name' => 'مخترق'])
            ->assertNotFound();
        $this->postJson(self::BASE . '/stock/adjust', [
            'category_id' => $catA->id, 'qty' => 1,
        ])->assertNotFound();
        $this->postJson(self::BASE . '/purchases', [
            'category_id' => $catA->id, 'qty' => 1, 'unit_price' => 1,
        ])->assertNotFound();
    }
}
