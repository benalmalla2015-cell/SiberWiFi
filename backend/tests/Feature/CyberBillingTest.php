<?php

namespace Tests\Feature;

use App\Models\CyberIdentity;
use App\Models\CyberPackage;
use App\Models\CyberSubscriber;
use App\Models\CyberSubscription;
use App\Models\CyberTopup;
use App\Models\CyberWallet;
use App\Models\User;
use App\Services\CyberBillingException;
use App\Services\CyberBillingService;
use App\Services\CyberRadiusService;
use App\Services\NotificationService;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * CYB-04 — billing, wallet, and cut-off over the real HTTP stack:
 * agent top-up (idempotent + FCM receipt via device tokens), atomic
 * package activation, RADIUS reply translation, engine event ingest
 * dedup, and the disconnect sweep.
 *
 * Self-contained like the acc suites: builds the minimal platform
 * tables it reads (users + region/directorate lookups that
 * cyber_subscribers FKs onto), then runs the real 2026_11_02_0000*
 * cyber migrations — CYB-03's subscriber tables and this sprint's.
 */
class CyberBillingTest extends TestCase
{
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
                $t->timestamp('email_verified_at')->nullable();
                $t->string('password');
                $t->rememberToken();
                $t->timestamps();
                $t->softDeletes();
            });
        }

        // Lookup stubs for cyber_subscribers' geography FKs.
        if (! Schema::hasTable('regions')) {
            Schema::create('regions', function (Blueprint $t) {
                $t->id();
                $t->string('name');
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('directorates')) {
            Schema::create('directorates', function (Blueprint $t) {
                $t->id();
                $t->foreignId('region_id')->constrained('regions')->cascadeOnDelete();
                $t->string('name');
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('sub_directorates')) {
            Schema::create('sub_directorates', function (Blueprint $t) {
                $t->id();
                $t->foreignId('directorate_id')->constrained('directorates')->cascadeOnDelete();
                $t->string('name');
                $t->timestamps();
            });
        }

        if (! Schema::hasTable('cyber_subscribers')) {
            foreach (
                glob(database_path('migrations/2026_11_02_0000*cyber*.php')) ?: []
                as $file
            ) {
                (require $file)->up();
            }
        }
    }

    // ── Fixtures ─────────────────────────────────────────────────

    private function agent(): User
    {
        return User::factory()->create(['type' => 'client']);
    }

    /** Per-test-instance geo rows (fresh :memory: DB per test). */
    private ?array $geo = null;

    private function geo(): array
    {
        if ($this->geo === null) {
            $regionId = DB::table('regions')->insertGetId(['name' => 'عدن']);
            $dirId = DB::table('directorates')->insertGetId(['region_id' => $regionId, 'name' => 'المعلا']);
            $subId = DB::table('sub_directorates')->insertGetId(['directorate_id' => $dirId, 'name' => 'المعلا']);
            $this->geo = [$dirId, $subId];
        }

        return $this->geo;
    }

    private function subscriber(
        string $simNo = '741234567',
        ?string $deviceId = 'dev-1',
        ?string $fcmToken = null,
        string $status = 'active',
    ): CyberSubscriber {
        [$dirId, $subId] = $this->geo();

        $subscriber = CyberSubscriber::create([
            'sim_no' => $simNo,
            'full_name' => 'مشترك تجريبي أحمد محمد',
            'directorate_id' => $dirId,
            'sub_directorate_id' => $subId,
            'status' => $status,
        ]);

        if ($deviceId !== null) {
            // fcm_token was added by CYB-04's alter — not in CYB-03's fillable.
            CyberIdentity::create([
                'subscriber_id' => $subscriber->id,
                'device_id' => $deviceId,
                'status' => 'issued',
            ])->forceFill(['fcm_token' => $fcmToken])->save();
        }

        return $subscriber;
    }

    private function fund(CyberSubscriber $subscriber, float $amount): CyberWallet
    {
        return CyberWallet::create([
            'subscriber_id' => $subscriber->id,
            'balance' => $amount,
            'currency' => 'YER',
        ]);
    }

    private function package(array $overrides = []): CyberPackage
    {
        return CyberPackage::create(array_merge([
            'name' => 'test-pack-'.uniqid(),
            'duration_days' => 7,
            'data_limit_gb' => 2,
            'price' => 800,
            'is_active' => true,
            'sort_order' => 9,
        ], $overrides));
    }

    // ── Top-up ───────────────────────────────────────────────────

    public function test_topup_credits_wallet_and_sends_fcm_receipt(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1', 'fcm-tok-1');
        Sanctum::actingAs($this->agent());
        $notifier = $this->spy(NotificationService::class);

        $response = $this->postJson('/api/cyber/topup', [
            'sim_no' => '741234567',
            'amount' => 1500,
            'idempotency_key' => 'topup-1',
        ]);

        $response->assertOk()->assertJsonPath('success', true);
        $this->assertSame('1500.00', (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance'));
        $this->assertDatabaseHas('cyber_topups', [
            'sim_no' => '741234567', 'amount' => 1500, 'status' => 'completed',
        ]);

        $notifier->shouldHaveReceived('sendToTokens')
            ->withArgs(function (array $tokens, string $title, string $body) {
                return $tokens === ['fcm-tok-1']
                    && str_contains($body, 'شحن رصيدك')
                    && str_contains($body, '1,500');
            })
            ->once();
    }

    public function test_topup_same_idempotency_key_does_not_double_credit(): void
    {
        $subscriber = $this->subscriber();
        Sanctum::actingAs($this->agent());

        $payload = [
            'sim_no' => '741234567',
            'amount' => 500,
            'idempotency_key' => 'same-key',
        ];
        $first = $this->postJson('/api/cyber/topup', $payload)->assertOk();
        $second = $this->postJson('/api/cyber/topup', $payload)->assertOk();

        $this->assertSame(
            '500.00',
            (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance')
        );
        $this->assertSame(1, CyberTopup::where('idempotency_key', 'same-key')->count());
        $this->assertFalse($first->json('data.duplicate'));
        $this->assertTrue($second->json('data.duplicate'));
    }

    public function test_topup_rejects_unknown_sim_and_malformed_number(): void
    {
        Sanctum::actingAs($this->agent());

        $this->postJson('/api/cyber/topup', [
            'sim_no' => '749999999', 'amount' => 100, 'idempotency_key' => 'k1',
        ])->assertNotFound();

        $this->postJson('/api/cyber/topup', [
            'sim_no' => '771234567', 'amount' => 100, 'idempotency_key' => 'k2',
        ])->assertUnprocessable();
    }

    public function test_topup_requires_auth(): void
    {
        $this->postJson('/api/cyber/topup', [
            'sim_no' => '741234567', 'amount' => 100, 'idempotency_key' => 'k3',
        ])->assertUnauthorized();
    }

    // ── Activation ───────────────────────────────────────────────

    public function test_activation_debits_wallet_atomically_and_builds_radius_reply(): void
    {
        $subscriber = $this->subscriber();
        $this->fund($subscriber, 800);
        $package = $this->package(['price' => 800, 'duration_days' => 7, 'data_limit_gb' => 2]);

        $subscription = app(CyberBillingService::class)->activate(
            (int) $subscriber->id, $package->id, 'act-1'
        );

        $this->assertSame('0.00', (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance'));
        $this->assertSame(CyberSubscription::STATUS_ACTIVE, $subscription->status);
        $this->assertSame(2 * 1024 * 1024 * 1024, $subscription->data_limit_bytes);
        $this->assertEqualsWithDelta(7 * 86400, $subscription->starts_at->diffInSeconds($subscription->ends_at), 2);
        $this->assertSame('10M/10M', $subscription->radius_reply['Mikrotik-Rate-Limit']);
        $this->assertSame(2 * 1024 * 1024 * 1024, $subscription->radius_reply['Mikrotik-Total-Limit']);

        // Idempotent retry returns the same subscription, no re-debit.
        $retry = app(CyberBillingService::class)->activate((int) $subscriber->id, $package->id, 'act-1');
        $this->assertSame($subscription->id, $retry->id);
        $this->assertSame(1, CyberSubscription::count());
    }

    public function test_activation_fails_cleanly_on_insufficient_balance(): void
    {
        $subscriber = $this->subscriber();
        $this->fund($subscriber, 100);
        $package = $this->package(['price' => 800]);

        try {
            app(CyberBillingService::class)->activate((int) $subscriber->id, $package->id);
            $this->fail('expected insufficient balance');
        } catch (CyberBillingException $e) {
            $this->assertSame(422, $e->status);
        }

        $this->assertSame('100.00', (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance'));
        $this->assertSame(0, CyberSubscription::count());
    }

    // ── Cut-off engine ───────────────────────────────────────────

    public function test_sweep_marks_time_expired_and_data_exhausted_subscriptions_ended(): void
    {
        $subscriber = $this->subscriber();
        $package = $this->package(['data_limit_gb' => 1]);
        $limit = 1024 * 1024 * 1024;

        $expired = CyberSubscription::create([
            'subscriber_id' => $subscriber->id, 'package_id' => $package->id,
            'starts_at' => now()->subDays(8), 'ends_at' => now()->subHour(),
            'data_limit_bytes' => $limit, 'consumed_bytes' => 10,
            'status' => 'active',
        ]);
        $exhausted = CyberSubscription::create([
            'subscriber_id' => $subscriber->id, 'package_id' => $package->id,
            'starts_at' => now()->subDay(), 'ends_at' => now()->addDay(),
            'data_limit_bytes' => $limit, 'consumed_bytes' => $limit,
            'status' => 'active',
        ]);
        $stillActive = CyberSubscription::create([
            'subscriber_id' => $subscriber->id, 'package_id' => $package->id,
            'starts_at' => now(), 'ends_at' => now()->addDay(),
            'data_limit_bytes' => $limit, 'consumed_bytes' => 5,
            'status' => 'active',
        ]);

        $stats = app(CyberRadiusService::class)->disconnectDue();

        $this->assertSame(2, $stats['ended']);
        $this->assertSame('expired', $expired->fresh()->status);
        $this->assertNotNull($expired->fresh()->ended_at);
        $this->assertSame('exhausted', $exhausted->fresh()->status);
        $this->assertSame('active', $stillActive->fresh()->status);
    }

    public function test_disconnect_due_command_runs(): void
    {
        $this->artisan('cyber:disconnect-due')->assertSuccessful();
    }

    // ── Packages endpoint ────────────────────────────────────────

    public function test_packages_endpoint_lists_active_packages(): void
    {
        $this->package(['name' => 'extra-active', 'price' => 50]);
        $this->package(['name' => 'disabled-pack', 'is_active' => false]);

        $response = $this->getJson('/api/cyber/packages')->assertOk();

        $names = collect($response->json('data'))->pluck('name');
        $this->assertContains('extra-active', $names);
        $this->assertNotContains('disabled-pack', $names);
        // Seeded pilot packages are present too.
        $this->assertContains('daily', $names);
        $this->assertContains('weekly', $names);
        $this->assertContains('monthly', $names);
    }

    // ── Engine-facing endpoints ──────────────────────────────────

    public function test_radius_events_dedup_and_usage_accumulation_ends_subscription(): void
    {
        config(['cyber.radius.engine_token' => 'engine-secret']);
        $subscriber = $this->subscriber();
        $package = $this->package(['data_limit_gb' => 1]);
        $limit = 1024 * 1024 * 1024;

        $subscription = CyberSubscription::create([
            'subscriber_id' => $subscriber->id, 'package_id' => $package->id,
            'starts_at' => now(), 'ends_at' => now()->addDay(),
            'data_limit_bytes' => $limit, 'consumed_bytes' => $limit - 100,
            'status' => 'active',
        ]);

        $headers = ['Authorization' => 'Bearer engine-secret'];
        $acct = fn (int $in, int $out, string $file, int $offset) => [
            'type' => 'acct.interim',
            'subscriber' => '741234567',
            'nas' => 'host-1',
            'nas_ip' => '10.0.0.2',
            'session_id' => 'sess-1',
            'attributes' => [
                'Acct-Input-Octets' => (string) $in,
                'Acct-Output-Octets' => (string) $out,
                'Acct-Session-Id' => 'sess-1',
            ],
            'source' => ['file' => $file, 'offset' => $offset],
        ];

        // Session start + first interim (+60 bytes consumed).
        $this->postJson('/api/cyber/radius/events', ['events' => [[
            'type' => 'acct.start', 'subscriber' => '741234567', 'nas' => 'host-1',
            'nas_ip' => '10.0.0.2', 'session_id' => 'sess-1',
            'attributes' => [], 'source' => ['file' => 'detail-20261102', 'offset' => 10],
        ], $acct(30, 30, 'detail-20261102', 20)]], $headers)->assertOk()
            ->assertJsonPath('data.accepted', 2);

        $this->assertSame($limit - 40, (int) $subscription->fresh()->consumed_bytes);
        $this->assertSame('active', $subscription->fresh()->status);

        // Re-deliver the same batch — deduped, no double count.
        $this->postJson('/api/cyber/radius/events', ['events' => [
            $acct(30, 30, 'detail-20261102', 20),
        ]], $headers)->assertOk()->assertJsonPath('data.duplicates', 1);
        $this->assertSame($limit - 40, (int) $subscription->fresh()->consumed_bytes);

        // Crossing the limit ends the subscription.
        $this->postJson('/api/cyber/radius/events', ['events' => [
            $acct(60, 60, 'detail-20261102', 30),
        ]], $headers)->assertOk();

        $this->assertSame('exhausted', $subscription->fresh()->status);
    }

    public function test_radius_endpoints_require_engine_token(): void
    {
        config(['cyber.radius.engine_token' => 'engine-secret']);

        $this->postJson('/api/cyber/radius/events', ['events' => []])->assertUnauthorized();
        $this->postJson('/api/cyber/radius/authorize', ['user' => '741234567'])
            ->assertUnauthorized();
    }

    public function test_authorize_returns_live_radius_reply(): void
    {
        config(['cyber.radius.engine_token' => 'engine-secret']);
        $subscriber = $this->subscriber();
        $package = $this->package(['rate_limit' => '20M/20M', 'data_limit_gb' => 1]);
        $limit = 1024 * 1024 * 1024;

        CyberSubscription::create([
            'subscriber_id' => $subscriber->id, 'package_id' => $package->id,
            'starts_at' => now(), 'ends_at' => now()->addDay(),
            'data_limit_bytes' => $limit, 'consumed_bytes' => 100,
            'status' => 'active',
            'radius_reply' => ['Mikrotik-Rate-Limit' => '20M/20M'],
        ]);

        $response = $this->postJson('/api/cyber/radius/authorize', [
            'user' => '741234567',
        ], ['Authorization' => 'Bearer engine-secret'])->assertOk();

        $reply = $response->json('data.reply');
        $this->assertSame('20M/20M', $reply['Mikrotik-Rate-Limit']);
        $this->assertSame($limit - 100, $reply['Mikrotik-Total-Limit']);
        $this->assertGreaterThan(80000, $reply['Session-Timeout']);

        // Subscriber with no active subscription is rejected.
        $this->postJson('/api/cyber/radius/authorize', [
            'user' => '741111111',
        ], ['Authorization' => 'Bearer engine-secret'])->assertForbidden();
    }

    // ── Subscriber device-bound endpoints ────────────────────────

    public function test_subscriber_activates_package_with_device_binding(): void
    {
        $subscriber = $this->subscriber('749876543', 'dev-9');
        $this->fund($subscriber, 1000);
        $package = $this->package(['price' => 800]);

        $this->postJson('/api/cyber/subscriptions', [
            'sim_no' => '749876543',
            'device_id' => 'dev-9',
            'package_id' => $package->id,
            'idempotency_key' => 'http-act-1',
        ])->assertOk()->assertJsonPath('data.status', 'active');

        $this->assertSame('200.00', (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance'));

        // A foreign device cannot spend the subscriber's wallet.
        $this->postJson('/api/cyber/subscriptions', [
            'sim_no' => '749876543',
            'device_id' => 'other-device',
            'package_id' => $package->id,
        ])->assertForbidden();
    }

    public function test_subscriber_current_balance_endpoint(): void
    {
        $subscriber = $this->subscriber('745550001', 'dev-7');
        $this->fund($subscriber, 350);

        $response = $this->getJson('/api/cyber/subscriptions/current?sim_no=745550001&device_id=dev-7')
            ->assertOk()
            ->assertJsonPath('data.subscription', null);
        $this->assertEquals(350, $response->json('data.balance'));
    }
}
