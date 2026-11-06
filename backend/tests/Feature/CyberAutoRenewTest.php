<?php

namespace Tests\Feature;

use App\Models\CyberCoveragePoint;
use App\Models\CyberIdentity;
use App\Models\CyberPackage;
use App\Models\CyberSubscriber;
use App\Models\CyberSubscription;
use App\Models\CyberWallet;
use App\Services\NotificationService;
use Database\Seeders\CyberCoveragePointSeeder;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * CYB-08 — auto-renew + coverage map over the real HTTP stack:
 * wallet-funded renewal chained onto the expiring window (atomic
 * debit via CyberBillingService::activate, idempotent on
 * "auto-renew-{id}"), insufficient-balance warning without renewal,
 * the device-bound PATCH toggle, and the public coverage endpoint.
 *
 * Self-contained like the other cyber suites: geo lookup stubs, then
 * the real 2026_11_02_0000* cyber migrations (which now include this
 * sprint's additive alter + coverage table).
 */
class CyberAutoRenewTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->createSchema();
    }

    private function createSchema(): void
    {
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
    ): CyberSubscriber {
        [$dirId, $subId] = $this->geo();

        $subscriber = CyberSubscriber::create([
            'sim_no' => $simNo,
            'full_name' => 'مشترك تجريبي أحمد محمد',
            'directorate_id' => $dirId,
            'sub_directorate_id' => $subId,
            'status' => 'active',
        ]);

        if ($deviceId !== null) {
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
            'name_ar' => 'باقة اختبار',
            'duration_days' => 30,
            'data_limit_gb' => 30,
            'price' => 1500,
            'is_active' => true,
            'sort_order' => 9,
        ], $overrides));
    }

    /** auto_renew isn't in CYB-04's fillable — set it post-create. */
    private function subscription(
        CyberSubscriber $subscriber,
        CyberPackage $package,
        \DateTimeInterface $endsAt,
        bool $autoRenew = true,
    ): CyberSubscription {
        $subscription = CyberSubscription::create([
            'subscriber_id' => $subscriber->id,
            'package_id' => $package->id,
            'starts_at' => now()->subDays(29),
            'ends_at' => $endsAt,
            'data_limit_bytes' => 30 * 1024 * 1024 * 1024,
            'consumed_bytes' => 0,
            'status' => CyberSubscription::STATUS_ACTIVE,
        ]);

        $subscription->forceFill(['auto_renew' => $autoRenew])->save();

        return $subscription;
    }

    // ── Auto-renew sweep ─────────────────────────────────────────

    public function test_auto_renew_debits_wallet_and_chains_renewal(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1', 'fcm-tok-1');
        $this->fund($subscriber, 3000);
        $package = $this->package(['price' => 1500, 'duration_days' => 30]);

        $endsAt = now()->addHours(12);
        $old = $this->subscription($subscriber, $package, $endsAt);

        $notifier = $this->spy(NotificationService::class);
        $this->artisan('cyber:auto-renew')->assertSuccessful();

        // Atomic debit through the billing path.
        $this->assertSame('1500.00', (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance'));

        $renewal = CyberSubscription::where('idempotency_key', 'auto-renew-'.$old->id)->first();
        $this->assertNotNull($renewal);
        $this->assertSame(CyberSubscription::STATUS_ACTIVE, $renewal->status);

        // The new window chains onto the old tail — the paid day isn't lost.
        $this->assertEqualsWithDelta(
            $endsAt->getTimestamp(),
            $renewal->starts_at->getTimestamp(),
            2
        );
        $this->assertEqualsWithDelta(
            $endsAt->getTimestamp() + 30 * 86400,
            $renewal->ends_at->getTimestamp(),
            2
        );
        $this->assertSame('10M/10M', $renewal->radius_reply['Mikrotik-Rate-Limit']);

        // Old subscription stays active until its natural ends_at.
        $this->assertSame(CyberSubscription::STATUS_ACTIVE, $old->fresh()->status);

        $notifier->shouldHaveReceived('sendToTokens')
            ->withArgs(function (array $tokens, string $title, string $body, array $data) {
                return $tokens === ['fcm-tok-1']
                    && str_contains($body, 'تجددت باقتك')
                    && $data['type'] === 'cyber_renewed';
            })
            ->once();
    }

    public function test_auto_renew_insufficient_balance_warns_without_renewing(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1', 'fcm-tok-1');
        $this->fund($subscriber, 100);
        $package = $this->package(['price' => 1500]);

        $this->subscription($subscriber, $package, now()->addHours(6));

        $notifier = $this->spy(NotificationService::class);
        $this->artisan('cyber:auto-renew')->assertSuccessful();

        $this->assertSame('100.00', (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance'));
        $this->assertSame(1, CyberSubscription::count());
        $this->assertSame(0, CyberSubscription::where('idempotency_key', 'like', 'auto-renew-%')->count());

        $notifier->shouldHaveReceived('sendToTokens')
            ->withArgs(function (array $tokens, string $title, string $body, array $data) {
                return $tokens === ['fcm-tok-1']
                    && str_contains($body, 'رصيد غير كافٍ')
                    && $data['type'] === 'cyber_renew_failed';
            })
            ->once();
    }

    public function test_sweep_only_touches_flagged_subscriptions_inside_the_window(): void
    {
        $subscriber = $this->subscriber();
        $this->fund($subscriber, 10000);
        $package = $this->package(['price' => 1500]);

        // Flag off — untouched even though it ends inside the window.
        $this->subscription($subscriber, $package, now()->addHours(10), false);
        // Flag on but ends beyond the 24h horizon — untouched for now.
        $this->subscription($subscriber, $package, now()->addDays(3), true);
        // Flag on inside the window — renews.
        $due = $this->subscription($subscriber, $package, now()->addHours(20), true);

        $this->artisan('cyber:auto-renew')->assertSuccessful();

        $this->assertSame('8500.00', (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance'));
        $this->assertSame(1, CyberSubscription::where('idempotency_key', 'auto-renew-'.$due->id)->count());
        $this->assertSame(4, CyberSubscription::count());

        // Re-running the sweep is idempotent — no second charge.
        $this->artisan('cyber:auto-renew')->assertSuccessful();
        $this->assertSame('8500.00', (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance'));
        $this->assertSame(4, CyberSubscription::count());
    }

    // ── PATCH toggle ─────────────────────────────────────────────

    public function test_toggle_auto_renew_is_device_bound(): void
    {
        $subscriber = $this->subscriber('749876543', 'dev-9');
        $package = $this->package();
        $subscription = $this->subscription($subscriber, $package, now()->addDays(10), false);

        $response = $this->patchJson("/api/cyber/subscriptions/{$subscription->id}/auto-renew", [
            'sim_no' => '749876543',
            'device_id' => 'dev-9',
            'auto_renew' => true,
        ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.auto_renew', true);
        $this->assertSame(1, (int) $subscription->fresh()->auto_renew);

        // Toggle back off.
        $this->patchJson("/api/cyber/subscriptions/{$subscription->id}/auto-renew", [
            'sim_no' => '749876543',
            'device_id' => 'dev-9',
            'auto_renew' => false,
        ])->assertOk()->assertJsonPath('data.auto_renew', false);
        $this->assertSame(0, (int) $subscription->fresh()->auto_renew);

        // A foreign device cannot arm the flag.
        $this->patchJson("/api/cyber/subscriptions/{$subscription->id}/auto-renew", [
            'sim_no' => '749876543',
            'device_id' => 'other-device',
            'auto_renew' => true,
        ])->assertForbidden();
        $this->assertSame(0, (int) $subscription->fresh()->auto_renew);
    }

    public function test_toggle_rejects_another_subscribers_subscription(): void
    {
        $owner = $this->subscriber('741111111', 'dev-1');
        $other = $this->subscriber('742222222', 'dev-2');
        $package = $this->package();
        $subscription = $this->subscription($owner, $package, now()->addDays(10));

        $this->patchJson("/api/cyber/subscriptions/{$subscription->id}/auto-renew", [
            'sim_no' => '742222222',
            'device_id' => 'dev-2',
            'auto_renew' => true,
        ])->assertNotFound();
    }

    // ── Coverage map ─────────────────────────────────────────────

    public function test_coverage_endpoint_returns_active_points(): void
    {
        $this->seed(CyberCoveragePointSeeder::class);

        CyberCoveragePoint::create([
            'name' => 'حي مخطط', 'city' => 'عدن',
            'latitude' => 12.8, 'longitude' => 45.0,
            'status' => 'planned',
        ]);

        $response = $this->getJson('/api/cyber/coverage')->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.ssid', 'CyberNet');

        $points = collect($response->json('data.points'));
        $pilot = $points->firstWhere('name', 'المعلا');

        $this->assertNotNull($pilot);
        $this->assertSame('عدن', $pilot['city']);
        $this->assertSame('HOST_PILOT', $pilot['host_name']);
        $this->assertEqualsWithDelta(12.7889, (float) $pilot['latitude'], 0.001);
        $this->assertEqualsWithDelta(45.0064, (float) $pilot['longitude'], 0.001);

        // Planned/offline points are not broadcast to the map.
        $this->assertNull($points->firstWhere('name', 'حي مخطط'));
    }
}
