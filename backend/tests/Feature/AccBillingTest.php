<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccPaymentRequest;
use App\Models\AccPlan;
use App\Models\AccSubscription;
use App\Models\User;
use App\Models\WalletLog;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-11 — the accounting subscription layer over the real HTTP
 * stack: trial auto-start, entitlements, wallet subscribe (locked
 * debit + WalletLog acc_subscription), manual transfer requests,
 * role gating, and tenant isolation.
 *
 * Self-contained like the other acc suites: it builds the minimal
 * platform tables it reads (users with wallet columns, wallet_logs,
 * bank_accounts, app_settings) plus this sprint's 1100* migrations.
 */
class AccBillingTest extends TestCase
{
    private const BASE = '/api/network-owner/accounting/billing';

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
                $t->decimal('balance', 14, 2)->default(0);
                $t->decimal('available_balance', 14, 2)->default(0);
                $t->timestamp('email_verified_at')->nullable();
                $t->string('password');
                $t->rememberToken();
                $t->timestamps();
                $t->softDeletes();
            });
        }
        // Wallet columns may be absent when another suite built users.
        foreach (['balance', 'available_balance'] as $col) {
            if (! Schema::hasColumn('users', $col)) {
                Schema::table('users', function (Blueprint $t) use ($col) {
                    $t->decimal($col, 14, 2)->default(0);
                });
            }
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
        if (! Schema::hasTable('acc_agents')) {
            foreach (
                glob(database_path('migrations/2026_10_27_0200*_create_acc_*.php')) ?: []
                as $file
            ) {
                (require $file)->up();
            }
        }
        if (! Schema::hasTable('wallet_logs')) {
            Schema::create('wallet_logs', function (Blueprint $t) {
                $t->id();
                $t->foreignId('user_id');
                $t->foreignId('counterparty_user_id')->nullable();
                $t->string('type');
                $t->decimal('amount', 14, 2);
                $t->decimal('balance_before', 14, 2)->default(0);
                $t->decimal('balance_after', 14, 2)->default(0);
                $t->string('description')->nullable();
                $t->string('reference_type')->nullable();
                $t->unsignedBigInteger('reference_id')->nullable();
                $t->foreignId('bank_account_id')->nullable();
                $t->string('transfer_receipt_number')->nullable();
                $t->string('sender_name')->nullable();
                $t->string('receipt_image')->nullable();
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('bank_accounts')) {
            Schema::create('bank_accounts', function (Blueprint $t) {
                $t->id();
                $t->string('bank_name')->nullable();
                $t->string('account_number')->nullable();
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('app_settings')) {
            Schema::create('app_settings', function (Blueprint $t) {
                $t->id();
                $t->string('key')->unique();
                $t->text('value')->nullable();
                $t->string('type')->default('string');
                $t->string('description')->nullable();
                $t->boolean('is_public')->default(false);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('acc_plans')) {
            foreach (
                glob(database_path('migrations/2026_10_29_1100*_*.php')) ?: []
                as $file
            ) {
                (require $file)->up();
            }
        }
    }

    // ── Fixtures ─────────────────────────────────────────────────

    private function owner(string $phone = '770000001', float $balance = 0): User
    {
        return User::factory()->create([
            'type' => 'network_owner', 'phone' => $phone, 'is_active' => true,
            'balance' => $balance, 'available_balance' => $balance,
        ]);
    }

    private function person(string $phone): User
    {
        return User::factory()->create([
            'type' => 'customer', 'phone' => $phone, 'is_active' => true,
        ]);
    }

    private function makeAgent(User $owner, User $user, string $role): AccAgent
    {
        return AccAgent::create([
            'network_owner_id' => $owner->id,
            'user_id' => $user->id,
            'role' => $role,
            'display_name' => $user->name,
            'status' => 'active',
        ]);
    }

    private function plan(array $over = []): AccPlan
    {
        return AccPlan::create(array_merge([
            'name' => 'الباقة الشهرية',
            'price' => 3000,
            'currency' => 'YER',
            'duration_days' => 30,
            'features' => ['acc.inventory', 'acc.reports'],
            'is_active' => true,
            'sort_order' => 1,
        ], $over));
    }

    // ── Trial + entitlements ─────────────────────────────────────

    public function test_entitlements_starts_trial_once_with_all_features(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $res = $this->getJson(self::BASE . '/entitlements')->assertOk();

        $this->assertTrue($res->json('success'));
        $this->assertSame('trial', $res->json('status'));
        $this->assertTrue($res->json('trialing'));
        $this->assertFalse($res->json('active'));
        $this->assertFalse($res->json('enforce')); // acc.enforce seeds '0'
        $this->assertSame(30, $res->json('trial_days'));
        $this->assertCount(28, $res->json('features'));
        $this->assertContains('acc.billing', $res->json('features'));

        $sub = AccSubscription::sole();
        $this->assertSame($owner->id, $sub->network_owner_id);
        $this->assertNull($sub->plan_id);
        $this->assertTrue($sub->ends_at->isFuture());

        // Idempotent check-in — no duplicate trial rows.
        $this->getJson(self::BASE . '/entitlements')->assertOk();
        $this->assertSame(1, AccSubscription::count());
    }

    public function test_no_retrial_after_a_historical_subscription(): void
    {
        $owner = $this->owner();
        AccSubscription::create([
            'network_owner_id' => $owner->id,
            'status' => 'expired',
            'starts_at' => now()->subDays(40),
            'ends_at' => now()->subDays(10),
        ]);
        Sanctum::actingAs($owner);

        $res = $this->getJson(self::BASE . '/entitlements')->assertOk();

        $this->assertSame('expired', $res->json('status'));
        $this->assertFalse($res->json('trialing'));
        $this->assertSame(1, AccSubscription::count());
        // Expired tenants keep only the free keys.
        $this->assertSame(
            ['acc.module', 'acc.dashboard', 'acc.billing'],
            $res->json('features')
        );
    }

    public function test_expired_running_trial_flips_to_expired(): void
    {
        $owner = $this->owner();
        AccSubscription::create([
            'network_owner_id' => $owner->id,
            'status' => 'trial',
            'starts_at' => now()->subDays(31),
            'ends_at' => now()->subDay(),
        ]);
        Sanctum::actingAs($owner);

        $res = $this->getJson(self::BASE . '/entitlements')->assertOk();

        $this->assertSame('expired', $res->json('status'));
        $this->assertSame('expired', AccSubscription::sole()->status);
    }

    // ── Plans ────────────────────────────────────────────────────

    public function test_plans_lists_active_only_with_gate_knobs(): void
    {
        $owner = $this->owner();
        $this->plan();
        $this->plan(['name' => 'معطلة', 'is_active' => false, 'sort_order' => 2]);
        Sanctum::actingAs($owner);

        $res = $this->getJson(self::BASE . '/plans')->assertOk();

        $this->assertCount(1, $res->json('data'));
        $this->assertSame('الباقة الشهرية', $res->json('data.0.name'));
        $this->assertEquals(3000.0, $res->json('data.0.price'));
        $this->assertSame(30, $res->json('trial_days'));
        $this->assertFalse($res->json('enforce'));
        $this->assertContains('acc.billing', $res->json('free_features'));
    }

    // ── Wallet subscribe ─────────────────────────────────────────

    public function test_wallet_subscribe_activates_tenant_and_logs_debit(): void
    {
        $owner = $this->owner('770000001', 10000);
        $plan = $this->plan();
        Sanctum::actingAs($owner);

        // Trial exists first — the paid sub must replace it.
        $this->getJson(self::BASE . '/entitlements')->assertOk();

        $res = $this->postJson(self::BASE . '/subscribe', ['plan_id' => $plan->id])
            ->assertOk();

        $this->assertTrue($res->json('success'));
        $this->assertSame('active', $res->json('data.status'));

        $active = AccSubscription::where('status', 'active')->sole();
        $this->assertSame($owner->id, $active->network_owner_id);
        $this->assertSame($plan->id, $active->plan_id);
        $this->assertTrue($active->ends_at->isFuture());
        $this->assertSame('expired', AccSubscription::where('status', 'expired')->sole()->status);

        $owner->refresh();
        $this->assertSame(7000.0, (float) $owner->balance);
        $this->assertSame(7000.0, (float) $owner->available_balance);

        $log = WalletLog::sole();
        $this->assertSame('debit', $log->type);
        $this->assertSame(3000.0, (float) $log->amount);
        $this->assertSame(10000.0, (float) $log->balance_before);
        $this->assertSame(7000.0, (float) $log->balance_after);
        $this->assertSame('acc_subscription', $log->reference_type);
        $this->assertSame($active->id, $log->reference_id);
    }

    public function test_subscribe_rejects_insufficient_balance_atomically(): void
    {
        $owner = $this->owner('770000001', 500);
        $plan = $this->plan();
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/subscribe', ['plan_id' => $plan->id])
            ->assertUnprocessable();

        $owner->refresh();
        $this->assertSame(500.0, (float) $owner->balance);
        $this->assertSame(0, WalletLog::count());
        $this->assertSame(0, AccSubscription::where('status', 'active')->count());
    }

    public function test_subscribe_rejects_inactive_plan(): void
    {
        $owner = $this->owner('770000001', 10000);
        $plan = $this->plan(['is_active' => false]);
        Sanctum::actingAs($owner);

        // exists passes but the active-scope findOrFail 404s.
        $this->postJson(self::BASE . '/subscribe', ['plan_id' => $plan->id])
            ->assertNotFound();
        $this->assertSame(0, WalletLog::count());
    }

    // ── Manual transfer requests ─────────────────────────────────

    public function test_payment_request_stores_pending_and_blocks_duplicates(): void
    {
        $owner = $this->owner();
        $plan = $this->plan();
        Sanctum::actingAs($owner);

        $res = $this->postJson(self::BASE . '/payments', [
            'plan_id' => $plan->id,
            'sender_name' => 'أحمد المودع',
            'transfer_receipt_number' => 'TRX-991',
        ])->assertCreated();

        $this->assertSame('pending', $res->json('data.status'));

        $req = AccPaymentRequest::sole();
        $this->assertSame($owner->id, $req->network_owner_id);
        $this->assertSame($owner->id, $req->user_id);
        $this->assertSame(3000.0, (float) $req->amount);
        $this->assertSame('أحمد المودع', $req->sender_name);

        // One pending per tenant.
        $this->postJson(self::BASE . '/payments', [
            'plan_id' => $plan->id,
            'sender_name' => 'محاولة ثانية',
        ])->assertUnprocessable();
        $this->assertSame(1, AccPaymentRequest::count());

        // List shows the tenant's requests.
        $rows = $this->getJson(self::BASE . '/payments')->assertOk()->json('data');
        $this->assertCount(1, $rows);
        $this->assertSame('الباقة الشهرية', $rows[0]['plan']);
        $this->assertSame('pending', $rows[0]['status']);
    }

    public function test_payment_request_requires_sender_name(): void
    {
        $owner = $this->owner();
        $plan = $this->plan();
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/payments', ['plan_id' => $plan->id])
            ->assertUnprocessable();
        $this->assertSame(0, AccPaymentRequest::count());
    }

    // ── Roles + tenant isolation ─────────────────────────────────

    public function test_agents_read_tenant_entitlements_but_cannot_pay(): void
    {
        $owner = $this->owner('770000001', 50000);
        $distUser = $this->person('771234010');
        $posUser = $this->person('771234011');
        $this->makeAgent($owner, $distUser, 'distributor');
        $this->makeAgent($owner, $posUser, 'pos');
        $plan = $this->plan();

        // Distributor probe resolves the *owner's* tenant trial.
        Sanctum::actingAs($distUser);
        $res = $this->getJson(self::BASE . '/entitlements')->assertOk();
        $this->assertSame('trial', $res->json('status'));
        $this->assertSame($owner->id, AccSubscription::sole()->network_owner_id);

        // Paid actions are owner/admin only.
        Sanctum::actingAs($posUser);
        $this->postJson(self::BASE . '/subscribe', ['plan_id' => $plan->id])
            ->assertForbidden();
        $this->getJson(self::BASE . '/plans')->assertForbidden();
        $this->getJson(self::BASE . '/payments')->assertForbidden();

        Sanctum::actingAs($distUser);
        $this->postJson(self::BASE . '/payments', [
            'plan_id' => $plan->id,
            'sender_name' => 'موزع',
        ])->assertForbidden();
    }

    public function test_tenant_isolation_between_owners(): void
    {
        $ownerA = $this->owner('770000001', 10000);
        $ownerB = $this->owner('770000002', 0);
        $plan = $this->plan();

        Sanctum::actingAs($ownerA);
        $this->postJson(self::BASE . '/subscribe', ['plan_id' => $plan->id])
            ->assertOk();

        Sanctum::actingAs($ownerB);
        $res = $this->getJson(self::BASE . '/entitlements')->assertOk();

        // B still gets its own fresh trial — A's paid sub is invisible.
        $this->assertSame('trial', $res->json('status'));
        $this->assertSame($ownerB->id,
            AccSubscription::where('status', 'trial')->sole()->network_owner_id);
        $this->assertSame($ownerA->id,
            AccSubscription::where('status', 'active')->sole()->network_owner_id);
    }

    public function test_accountless_user_gets_clean_403(): void
    {
        Sanctum::actingAs($this->person('778889990'));

        $this->getJson(self::BASE . '/entitlements')->assertForbidden();
    }
}
