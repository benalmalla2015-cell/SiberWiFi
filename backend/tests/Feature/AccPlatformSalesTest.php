<?php

namespace Tests\Feature;

use App\Models\AccAccount;
use App\Models\AccCardCategory;
use App\Models\AccJournalEntry;
use App\Models\AccStock;
use App\Models\AccStockMovement;
use App\Models\User;
use App\Services\AccPlatformException;
use App\Services\AccPlatformReadOnly;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-08 — customer-app sale posting: the read-only scanner turns
 * completed wallet purchases into card_purchase_platform entries +
 * stock out, idempotently, inside the platform write-ban guard.
 *
 * Self-contained like the sibling suites: minimal users/networks/
 * card_categories/cards/transactions/transaction_cards schema plus
 * the acc_* migrations (incl. 2026_10_29_080001 acc_posting_map).
 */
class AccPlatformSalesTest extends TestCase
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
        if (! Schema::hasTable('transactions')) {
            Schema::create('transactions', function (Blueprint $t) {
                $t->id();
                $t->string('transaction_number')->unique();
                $t->foreignId('user_id');
                $t->foreignId('network_id');
                $t->unsignedBigInteger('card_id')->nullable();
                $t->foreignId('category_id');
                $t->unsignedInteger('quantity')->default(1);
                $t->decimal('unit_price', 12, 2);
                $t->decimal('total_amount', 12, 2);
                $t->decimal('discount_amount', 12, 2)->default(0);
                $t->decimal('cashback_amount', 12, 2)->default(0);
                $t->decimal('commission_amount', 12, 2)->default(0);
                $t->decimal('network_owner_amount', 12, 2)->default(0);
                $t->decimal('balance_before', 12, 2)->default(0);
                $t->decimal('balance_after', 12, 2)->default(0);
                $t->string('status', 12)->default('completed');
                $t->string('payment_method', 12)->default('wallet');
                $t->boolean('is_advance')->default(false);
                $t->string('advance_status', 20)->nullable();
                $t->decimal('native_amount', 12, 2)->nullable();
                $t->string('network_currency', 10)->default('north');
                $t->string('buyer_currency', 10)->default('north');
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('transaction_cards')) {
            Schema::create('transaction_cards', function (Blueprint $t) {
                $t->id();
                $t->foreignId('transaction_id');
                $t->foreignId('card_id');
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('wallet_logs')) {
            Schema::create('wallet_logs', function (Blueprint $t) {
                $t->id();
                $t->foreignId('user_id');
                $t->string('type', 12);
                $t->decimal('amount', 12, 2);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('exchange_rate_settings')) {
            Schema::create('exchange_rate_settings', function (Blueprint $t) {
                $t->id();
                $t->string('base_currency', 10)->default('north');
                $t->decimal('rate_percent', 12, 4)->default(100);
                $t->boolean('is_active')->default(true);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('acc_posting_map')) {
            foreach ([
                ...glob(database_path('migrations/2026_10_26_0100*_create_acc_*.php')) ?: [],
                database_path('migrations/2026_10_27_020001_create_acc_agents_table.php'),
                ...glob(database_path('migrations/2026_10_27_0300*_create_acc_*.php')) ?: [],
                database_path('migrations/2026_10_29_080001_create_acc_posting_map_table.php'),
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

    private function card(int $networkId, int $catId, string $status = 'sold', string $source = 'platform'): int
    {
        return (int) DB::table('cards')->insertGetId([
            'network_id' => $networkId,
            'category_id' => $catId,
            'card_number' => 'c' . uniqid(),
            'status' => $status,
            'source' => $source,
        ]);
    }

    /**
     * A real-shaped wallet sale exactly as TransactionController::purchase
     * writes it — buyer paid `total`, platform took `commission`,
     * owner netted `owner` (all in the network's currency).
     */
    private function sale(
        int $userId, int $networkId, int $catId, array $cardIds,
        float $native, float $commission, array $over = []
    ): int {
        $txId = (int) DB::table('transactions')->insertGetId(array_merge([
            'transaction_number' => 'TRX-' . strtoupper(uniqid()),
            'user_id' => $userId,
            'network_id' => $networkId,
            'card_id' => $cardIds[0] ?? null,
            'category_id' => $catId,
            'quantity' => max(1, count($cardIds)),
            'unit_price' => $native / max(1, count($cardIds)),
            'total_amount' => $native,
            'discount_amount' => 0,
            'cashback_amount' => 0,
            'commission_amount' => $commission,
            'network_owner_amount' => $native - $commission,
            'balance_before' => 5000,
            'balance_after' => 5000 - $native,
            'status' => 'completed',
            'payment_method' => 'wallet',
            'is_advance' => false,
            'native_amount' => $native,
            'network_currency' => 'north',
            'buyer_currency' => 'north',
            'created_at' => now(),
            'updated_at' => now(),
        ], $over));

        foreach ($cardIds as $cid) {
            DB::table('transaction_cards')->insert([
                'transaction_id' => $txId, 'card_id' => $cid,
            ]);
        }

        return $txId;
    }

    private function sync(User $owner, int $limit = 200): array
    {
        Sanctum::actingAs($owner);

        return $this->postJson(self::BASE . '/platform-sales/sync', ['limit' => $limit])
            ->assertOk()->json('data');
    }

    // ── The acceptance criterion ─────────────────────────────────

    public function test_wallet_sale_posts_balanced_entry_and_stock(): void
    {
        $owner = $this->owner();
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'باقة ٥٠٠', 500);
        $c1 = $this->card($netId, $catId);
        $c2 = $this->card($netId, $catId);

        $txId = $this->sale($owner->id, $netId, $catId, [$c1, $c2], 1000, 50);

        $stats = $this->sync($owner);
        $this->assertSame(1, $stats['scanned']);
        $this->assertSame(1, $stats['posted']);
        $this->assertSame([], $stats['errors']);

        $entry = AccJournalEntry::sole();
        $this->assertSame('card_purchase_platform', $entry->doc_type);
        $this->assertSame($txId, $entry->doc_ref_id);
        $this->assertSame('platform-sale-' . $txId, $entry->idempotency_key);
        $this->assertStringContainsString('بيع كرت', $entry->memo);

        $lines = $entry->lines;
        $this->assertEquals(
            (float) $lines->sum('debit'),
            (float) $lines->sum('credit')
        );
        // Dr cash 950 (net) + Dr commission 50 = Cr revenue 1000.
        $this->assertSame(950.0, (float) $lines->firstWhere('account_code', AccAccount::CASH_MAIN)->debit);
        $this->assertSame(50.0, (float) $lines->firstWhere('account_code', AccAccount::EXPENSES)->debit);
        $this->assertSame(1000.0, (float) $lines->firstWhere('account_code', AccAccount::REVENUE_SALES)->credit);

        // Stock: each platform card got in+sale → net zero on a
        // never-stocked bucket, full audit trail preserved.
        $accCat = AccCardCategory::where('card_category_id', $catId)->sole();
        $this->assertSame('platform', $accCat->source_binding);
        $this->assertSame(0.0, (float) AccStock::where('category_id', $accCat->id)->sole()->qty);
        $this->assertSame(2, AccStockMovement::where('type', 'in')->count());
        $this->assertSame(2, AccStockMovement::where('type', 'sale')->count());
        $this->assertSame(-1.0, (float) AccStockMovement::where('type', 'sale')->first()->qty);
    }

    public function test_replay_never_duplicates_entry_or_stock(): void
    {
        $owner = $this->owner();
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'باقة', 200);
        $this->sale($owner->id, $netId, $catId, [$this->card($netId, $catId)], 200, 10);

        $first = $this->sync($owner);
        $this->assertSame(1, $first['posted']);

        $again = $this->sync($owner);
        $this->assertSame(0, $again['posted']);
        $this->assertSame(1, $again['skipped']);

        $this->assertSame(1, AccJournalEntry::count());
        $this->assertSame(1, AccStockMovement::where('type', 'in')->count());
        $this->assertSame(1, AccStockMovement::where('type', 'sale')->count());
    }

    public function test_only_completed_paid_sales_are_posted(): void
    {
        $owner = $this->owner();
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'باقة', 300);
        $card = $this->card($netId, $catId);

        foreach (['pending', 'failed', 'refunded'] as $status) {
            $this->sale($owner->id, $netId, $catId, [$card], 300, 15, ['status' => $status]);
        }
        // سلفني — outstanding debt, not a paid sale.
        $this->sale($owner->id, $netId, $catId, [$card], 300, 15, [
            'payment_method' => 'advance', 'is_advance' => true,
            'advance_status' => 'outstanding',
        ]);
        $this->sale($owner->id, $netId, $catId, [$card], 300, 15);

        $stats = $this->sync($owner);
        $this->assertSame(1, $stats['scanned']);
        $this->assertSame(1, $stats['posted']);
        $this->assertSame(1, AccJournalEntry::count());
    }

    public function test_mikrotik_card_is_never_double_counted(): void
    {
        $owner = $this->owner();
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'راوتر ١٠٠', 100);
        // A router card already imported by ACC-02's sync, then sold
        // through the customer app.
        $mk = $this->card($netId, $catId, 'sold', 'mikrotik');
        $this->sale($owner->id, $netId, $catId, [$mk], 100, 5);

        Sanctum::actingAs($owner);
        // Router sync first: in + sale.
        $this->postJson(self::BASE . '/stock/sync')->assertOk();
        $this->assertSame(1, AccStockMovement::where('type', 'sale')->count());

        // Platform poster: entry created, but no second sale movement.
        $stats = $this->sync($owner);
        $this->assertSame(1, $stats['posted']);
        $this->assertSame(1, AccJournalEntry::count());
        $this->assertSame(1, AccStockMovement::where('type', 'sale')->count());
        $this->assertSame(1, AccStockMovement::where('type', 'in')->count());

        // Reverse order: platform first, then router sync — still one pair.
        $mk2 = $this->card($netId, $catId, 'sold', 'mikrotik');
        $this->sale($owner->id, $netId, $catId, [$mk2], 100, 5);
        $this->sync($owner);
        $this->postJson(self::BASE . '/stock/sync')->assertOk();
        $this->assertSame(2, AccStockMovement::where('type', 'sale')->count());
        $this->assertSame(2, AccStockMovement::where('type', 'in')->count());
    }

    public function test_cards_without_links_use_transaction_ref_and_remainder(): void
    {
        $owner = $this->owner();
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'باقة', 150);

        // quantity=2 but no transaction_cards rows and no card_id.
        $txId = (int) DB::table('transactions')->insertGetId([
            'transaction_number' => 'TRX-NOCARDS',
            'user_id' => $owner->id, 'network_id' => $netId,
            'card_id' => null, 'category_id' => $catId,
            'quantity' => 2, 'unit_price' => 150, 'total_amount' => 300,
            'commission_amount' => 15, 'network_owner_amount' => 285,
            'status' => 'completed', 'payment_method' => 'wallet',
            'is_advance' => false, 'native_amount' => 300,
            'network_currency' => 'north', 'buyer_currency' => 'north',
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $stats = $this->sync($owner);
        $this->assertSame(1, $stats['posted']);

        $in = AccStockMovement::where('ref_type', 'platform_transaction')
            ->where('ref_id', $txId)->where('type', 'in')->sole();
        $this->assertSame(2.0, (float) $in->qty);
        $this->assertSame(-2.0, (float) AccStockMovement::where('ref_type', 'platform_transaction')
            ->where('ref_id', $txId)->where('type', 'sale')->sole()->qty);
        $this->assertSame(300.0, (float) AccJournalEntry::sole()->lines
            ->firstWhere('account_code', AccAccount::REVENUE_SALES)->credit);
    }

    // ── The security ban — enforced in code ──────────────────────

    public function test_platform_write_inside_guard_throws_and_rolls_back(): void
    {
        $owner = $this->owner();
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'باقة', 100);

        $before = DB::table('transactions')->count();

        $this->expectException(AccPlatformException::class);
        try {
            AccPlatformReadOnly::run(function () use ($owner, $netId, $catId) {
                DB::transaction(function () use ($owner, $netId, $catId) {
                    DB::table('transactions')->insert([
                        'transaction_number' => 'TRX-HACK',
                        'user_id' => $owner->id, 'network_id' => $netId,
                        'category_id' => $catId, 'quantity' => 1,
                        'unit_price' => 1, 'total_amount' => 1,
                        'status' => 'completed', 'payment_method' => 'wallet',
                        'created_at' => now(), 'updated_at' => now(),
                    ]);
                });
            });
        } finally {
            $this->assertSame($before, DB::table('transactions')->count());
            $this->assertFalse(AccPlatformReadOnly::armed());
        }
    }

    public function test_sync_leaves_platform_tables_untouched(): void
    {
        $owner = $this->owner();
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'باقة', 100);
        $this->sale($owner->id, $netId, $catId, [$this->card($netId, $catId)], 100, 5);

        $snapshot = fn () => [
            'transactions' => DB::table('transactions')->count(),
            'cards' => DB::table('cards')->count(),
            'wallet_logs' => DB::table('wallet_logs')->count(),
            'statuses' => DB::table('cards')->pluck('status')->all(),
        ];
        $before = $snapshot();

        $this->sync($owner);

        $this->assertSame($before, $snapshot());
    }

    // ── Posting map + multi-currency ─────────────────────────────

    public function test_posting_map_overrides_accounts(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'باقة', 500);

        $this->getJson(self::BASE . '/posting-map')
            ->assertOk()
            ->assertJsonPath('data.0.mapping.cash_account', AccAccount::CASH_MAIN);

        $this->putJson(self::BASE . '/posting-map', [
            'source' => 'card_purchase_platform',
            'mapping' => ['cash_account' => AccAccount::AR_DISTRIBUTORS],
        ])->assertOk()
            ->assertJsonPath('data.mapping.cash_account', AccAccount::AR_DISTRIBUTORS)
            ->assertJsonPath('data.mapping.revenue_account', AccAccount::REVENUE_SALES);

        $this->sale($owner->id, $netId, $catId, [$this->card($netId, $catId)], 500, 25);
        $this->postJson(self::BASE . '/platform-sales/sync')->assertOk();

        $entry = AccJournalEntry::sole();
        $this->assertSame(
            475.0,
            (float) $entry->lines->firstWhere('account_code', AccAccount::AR_DISTRIBUTORS)->debit
        );

        // Unknown account codes are refused.
        $this->putJson(self::BASE . '/posting-map', [
            'source' => 'card_purchase_platform',
            'mapping' => ['cash_account' => '9999'],
        ])->assertUnprocessable();
    }

    public function test_south_network_sale_posts_in_base_currency(): void
    {
        DB::table('exchange_rate_settings')->insert([
            'base_currency' => 'north', 'rate_percent' => 400, 'is_active' => true,
        ]);

        $owner = $this->owner();
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'جنوب', 400);
        $this->sale($owner->id, $netId, $catId, [$this->card($netId, $catId)], 4000, 200, [
            'network_currency' => 'south', 'total_amount' => 4000,
        ]);

        $this->sync($owner);

        $entry = AccJournalEntry::sole();
        $this->assertSame('south', $entry->currency);
        $this->assertSame(0.25, (float) $entry->exchange_rate);
        // 4000 south = 1000 north; commission 200 south = 50 north.
        $this->assertSame(1000.0, (float) $entry->lines
            ->firstWhere('account_code', AccAccount::REVENUE_SALES)->credit);
        $this->assertSame(950.0, (float) $entry->lines
            ->firstWhere('account_code', AccAccount::CASH_MAIN)->debit);
    }

    // ── Endpoints + isolation ────────────────────────────────────

    public function test_index_lazy_syncs_and_lists_entries(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $netId = $this->networkFor($owner);
        $catId = $this->platformCategory($netId, 'باقة', 250);
        $this->sale($owner->id, $netId, $catId, [$this->card($netId, $catId)], 250, 12);

        $res = $this->getJson(self::BASE . '/platform-sales');
        $res->assertOk()
            ->assertJsonPath('sync.posted', 1)
            ->assertJsonCount(1, 'data.data');
        $this->assertSame(
            'card_purchase_platform',
            AccJournalEntry::sole()->doc_type
        );
    }

    public function test_platform_sales_are_tenant_isolated(): void
    {
        $ownerA = $this->owner('770000001');
        $ownerB = $this->owner('770000002');
        $netB = $this->networkFor($ownerB);
        $catB = $this->platformCategory($netB, 'باقة ب', 100);
        $this->sale($ownerB->id, $netB, $catB, [$this->card($netB, $catB)], 100, 5);

        // A sees nothing — B's transactions are out of scope.
        $statsA = $this->sync($ownerA);
        $this->assertSame(0, $statsA['scanned']);
        $this->assertSame(0, AccJournalEntry::count());

        // B's run posts exactly B's sale.
        $statsB = $this->sync($ownerB);
        $this->assertSame(1, $statsB['posted']);
        $this->assertSame(
            $ownerB->id,
            AccJournalEntry::sole()->network_owner_id
        );
    }
}
