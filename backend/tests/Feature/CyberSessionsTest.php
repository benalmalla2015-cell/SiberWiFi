<?php

namespace Tests\Feature;

use App\Models\CyberIdentity;
use App\Models\CyberRadiusEvent;
use App\Models\CyberSession;
use App\Models\CyberSubscriber;
use App\Models\CyberSubscription;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * CYB-09 — subscriber session log, daily usage chart data, and the
 * reconcile report over seeded data:
 *
 * - GET /api/cyber/sessions returns live + closed rows newest-first,
 *   scoped to the device-bound SIM only.
 * - GET /api/cyber/usage/daily buckets acct interim/stop deltas into
 *   their calendar days and zero-fills quiet days.
 * - cyber:reconcile-report passes on matching books and fails loudly
 *   when RADIUS records disagree with what billing debited.
 *
 * Self-contained like CyberBillingTest: builds the minimal lookup
 * tables cyber_subscribers FKs onto, then runs the real
 * 2026_11_02_0000* cyber migrations.
 */
class CyberSessionsTest extends TestCase
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
            ]);
        }

        return $subscriber;
    }

    private function radiusSession(CyberSubscriber $subscriber, array $overrides = []): CyberSession
    {
        return CyberSession::create(array_merge([
            'subscriber_id' => $subscriber->id,
            'sim_no' => $subscriber->sim_no,
            'nas_identifier' => 'host-1',
            'nas_ip' => '10.0.0.2',
            'session_id' => 'sess-'.uniqid(),
            'started_at' => now(),
            'last_seen_at' => now(),
            'input_octets' => 0,
            'output_octets' => 0,
            'status' => 'active',
        ], $overrides));
    }

    private function acctEvent(
        CyberSession $session,
        string $type,
        int $inputTotal,
        int $outputTotal,
        string $loggedAt,
        int $offset,
        string $file = 'detail-ledger',
    ): CyberRadiusEvent {
        return CyberRadiusEvent::create([
            'source_file' => $file,
            'source_offset' => $offset,
            'type' => $type,
            'sim_no' => $session->sim_no,
            'session_id' => $session->session_id,
            'payload' => [
                'type' => $type,
                'subscriber' => $session->sim_no,
                'nas' => $session->nas_identifier,
                'session_id' => $session->session_id,
                'logged_at' => $loggedAt,
                'attributes' => [
                    'Acct-Input-Octets' => (string) $inputTotal,
                    'Acct-Output-Octets' => (string) $outputTotal,
                ],
            ],
            'processed_at' => now(),
        ]);
    }

    // ── Session log ──────────────────────────────────────────────

    public function test_sessions_returns_live_and_closed_ordered_newest_first(): void
    {
        $subscriber = $this->subscriber();

        $old = $this->radiusSession($subscriber, [
            'session_id' => 'sess-old',
            'started_at' => now()->subDays(3),
            'closed_at' => now()->subDays(3)->addHours(2),
            'last_seen_at' => now()->subDays(3)->addHours(2),
            'status' => 'closed',
            'close_reason' => 'acct_stop',
            'input_octets' => 100,
            'output_octets' => 300,
        ]);
        $newest = $this->radiusSession($subscriber, [
            'session_id' => 'sess-live',
            'started_at' => now()->subHour(),
            'last_seen_at' => now(),
            'status' => 'active',
            'input_octets' => 50,
            'output_octets' => 50,
        ]);
        $mid = $this->radiusSession($subscriber, [
            'session_id' => 'sess-mid',
            'started_at' => now()->subDay(),
            'closed_at' => now()->subDay()->addHour(),
            'status' => 'closed',
            'close_reason' => 'coa_disconnect',
            'input_octets' => 1000,
            'output_octets' => 500,
        ]);

        $response = $this->getJson('/api/cyber/sessions?sim_no=741234567&device_id=dev-1')
            ->assertOk()
            ->assertJsonPath('data.sim_no', '741234567');

        $ids = array_column($response->json('data.sessions'), 'id');
        $this->assertSame([$newest->id, $mid->id, $old->id], $ids);

        $live = $response->json('data.sessions.0');
        $this->assertSame('host-1', $live['host']);
        $this->assertSame('10.0.0.2', $live['nas_ip']);
        $this->assertSame('active', $live['status']);
        $this->assertSame(100, $live['total_bytes']);
        $this->assertNull($live['ended_at']);
        $this->assertNotNull($live['started_at']);

        $closed = $response->json('data.sessions.2');
        $this->assertSame('closed', $closed['status']);
        $this->assertSame('acct_stop', $closed['close_reason']);
        $this->assertSame(400, $closed['total_bytes']);
        $this->assertNotNull($closed['ended_at']);
        $this->assertSame(7200, $closed['duration_seconds']);

        $response->assertJsonPath('data.summary.count', 3)
            ->assertJsonPath('data.summary.active', 1)
            ->assertJsonPath('data.summary.total_bytes', 2000);
    }

    public function test_sessions_is_scoped_to_the_bound_sim(): void
    {
        $mine = $this->subscriber('741234567', 'dev-1');
        $other = $this->subscriber('749999999', 'dev-2');

        $this->radiusSession($mine, ['input_octets' => 10, 'output_octets' => 10]);
        $this->radiusSession($other, ['input_octets' => 999, 'output_octets' => 999]);

        $response = $this->getJson('/api/cyber/sessions?sim_no=741234567&device_id=dev-1')
            ->assertOk();

        $this->assertCount(1, $response->json('data.sessions'));
        $response->assertJsonPath('data.summary.total_bytes', 20);
    }

    public function test_sessions_rejects_unbound_device(): void
    {
        $this->subscriber('741234567', 'dev-1');

        $this->getJson('/api/cyber/sessions?sim_no=741234567&device_id=stranger')
            ->assertForbidden()
            ->assertJsonPath('success', false);

        $this->getJson('/api/cyber/sessions?device_id=dev-1')
            ->assertUnprocessable();
    }

    // ── Daily usage ──────────────────────────────────────────────

    public function test_daily_usage_buckets_event_deltas_by_day(): void
    {
        $subscriber = $this->subscriber();
        $session = $this->radiusSession($subscriber, [
            'session_id' => 'sess-daily',
            'started_at' => now()->subDays(10),
            'input_octets' => 700,
            'output_octets' => 700,
        ]);

        // Pre-window anchor: cumulative 200 total, dropped from the
        // chart but re-bases the next delta.
        $this->acctEvent($session, 'acct.interim', 100, 100, now()->subDays(10)->toDateTimeString(), 1);
        // Day before yesterday: 600 cumulative → +400.
        $this->acctEvent($session, 'acct.interim', 300, 300, now()->subDays(2)->toDateTimeString(), 2);
        // Yesterday: 1200 cumulative → +600.
        $this->acctEvent($session, 'acct.interim', 600, 600, now()->subDay()->toDateTimeString(), 3);
        // Today (stop): 1400 cumulative → +200.
        $this->acctEvent($session, 'acct.stop', 700, 700, now()->toDateTimeString(), 4);

        $response = $this->getJson('/api/cyber/usage/daily?sim_no=741234567&device_id=dev-1&days=7')
            ->assertOk()
            ->assertJsonPath('data.days', 7);

        $daily = collect($response->json('data.daily'))->keyBy('date');
        $this->assertCount(7, $daily);

        $byDate = fn (int $daysAgo) => $daily[now()->subDays($daysAgo)->toDateString()]['bytes'];

        $this->assertSame(400, $byDate(2));
        $this->assertSame(600, $byDate(1));
        $this->assertSame(200, $byDate(0));
        // Quiet days are zero-filled.
        $this->assertSame(0, $byDate(3));
        $response->assertJsonPath('data.total_bytes', 1200);
    }

    public function test_daily_usage_anchors_eventless_session_to_last_activity_day(): void
    {
        $subscriber = $this->subscriber();
        $this->radiusSession($subscriber, [
            'started_at' => now()->subDays(2),
            'closed_at' => now()->subDays(2)->addHours(3),
            'last_seen_at' => now()->subDays(2)->addHours(3),
            'status' => 'closed',
            'input_octets' => 2048,
            'output_octets' => 1024,
        ]);

        $response = $this->getJson('/api/cyber/usage/daily?sim_no=741234567&device_id=dev-1&days=7')
            ->assertOk();

        $daily = collect($response->json('data.daily'))->keyBy('date');
        $this->assertSame(3072, $daily[now()->subDays(2)->toDateString()]['bytes']);
        $response->assertJsonPath('data.total_bytes', 3072);
    }

    public function test_daily_usage_validates_window_and_device(): void
    {
        $this->subscriber('741234567', 'dev-1');

        $this->getJson('/api/cyber/usage/daily?sim_no=741234567&device_id=dev-1&days=14')
            ->assertUnprocessable();
        $this->getJson('/api/cyber/usage/daily?sim_no=741234567&device_id=stranger&days=30')
            ->assertForbidden();
    }

    // ── Reconcile report ─────────────────────────────────────────

    public function test_reconcile_report_is_clean_when_radius_matches_billing(): void
    {
        $subscriber = $this->subscriber();
        $sub = CyberSubscription::create([
            'subscriber_id' => $subscriber->id,
            'package_id' => DB::table('cyber_packages')->value('id'),
            'starts_at' => now()->subDay(),
            'ends_at' => now()->addDay(),
            'data_limit_bytes' => 1024 * 1024 * 1024,
            'consumed_bytes' => 1500,
            'status' => 'active',
        ]);
        $this->radiusSession($subscriber, [
            'subscription_id' => $sub->id,
            'input_octets' => 1000,
            'output_octets' => 500,
        ]);

        $this->artisan('cyber:reconcile-report')
            ->expectsOutputToContain('reconcile clean')
            ->assertSuccessful();
    }

    public function test_reconcile_report_flags_billing_drift_and_unattributed_bytes(): void
    {
        $subscriber = $this->subscriber();
        $sub = CyberSubscription::create([
            'subscriber_id' => $subscriber->id,
            'package_id' => DB::table('cyber_packages')->value('id'),
            'starts_at' => now()->subDay(),
            'ends_at' => now()->addDay(),
            'data_limit_bytes' => 1024 * 1024 * 1024,
            'consumed_bytes' => 1500, // billing says 1500…
            'status' => 'active',
        ]);
        // …RADIUS only recorded 500 on the linked session.
        $this->radiusSession($subscriber, [
            'subscription_id' => $sub->id,
            'input_octets' => 400,
            'output_octets' => 100,
        ]);
        // Plus traffic no package ever absorbed.
        $this->radiusSession($subscriber, [
            'subscription_id' => null,
            'session_id' => 'sess-orphan',
            'input_octets' => 60,
            'output_octets' => 40,
        ]);

        $this->artisan('cyber:reconcile-report')
            ->expectsOutputToContain('mismatched=1')
            ->expectsOutputToContain('unattributed session bytes: 100')
            ->assertExitCode(1);
    }

    public function test_reconcile_report_scopes_to_one_sim(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1');
        $other = $this->subscriber('749999999', 'dev-2');

        foreach ([$subscriber, $other] as $owner) {
            $sub = CyberSubscription::create([
                'subscriber_id' => $owner->id,
                'package_id' => DB::table('cyber_packages')->value('id'),
                'starts_at' => now()->subDay(),
                'ends_at' => now()->addDay(),
                'consumed_bytes' => 100,
                'status' => 'active',
            ]);
            $this->radiusSession($owner, [
                'subscription_id' => $sub->id,
                'input_octets' => 60,
                'output_octets' => 40,
            ]);
        }

        $this->artisan('cyber:reconcile-report', ['--sim' => '741234567'])
            ->expectsOutputToContain('checked=1 matched=1 mismatched=0')
            ->assertSuccessful();
    }
}
