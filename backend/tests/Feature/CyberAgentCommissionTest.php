<?php

namespace Tests\Feature;

use App\Models\CyberAgentCommission;
use App\Models\CyberSubscriber;
use App\Models\CyberTopup;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * CYB-07 — agent commissions + agent endpoints over the real HTTP
 * stack: a completed top-up accrues a configurable commission, an
 * idempotent retry never double-credits, the read endpoints serve
 * "أرباحي" and "سجل عملياتي", and reconcile() backfills rows whose
 * event was missed.
 *
 * Same self-contained pattern as CyberBillingTest: minimal platform
 * tables + the real 2026_11_02_0000* cyber migrations (the glob now
 * picks up 000008 cyber_agent_commissions too).
 */
class CyberAgentCommissionTest extends TestCase
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

    private function subscriber(string $simNo = '741234567'): CyberSubscriber
    {
        $regionId = DB::table('regions')->insertGetId(['name' => 'عدن']);
        $dirId = DB::table('directorates')->insertGetId(['region_id' => $regionId, 'name' => 'المعلا']);
        $subId = DB::table('sub_directorates')->insertGetId(['directorate_id' => $dirId, 'name' => 'المعلا']);

        return CyberSubscriber::create([
            'sim_no' => $simNo,
            'full_name' => 'مشترك تجريبي أحمد محمد',
            'directorate_id' => $dirId,
            'sub_directorate_id' => $subId,
            'status' => 'active',
        ]);
    }

    private function topup(string $key, float $amount = 1000, string $simNo = '741234567')
    {
        return $this->postJson('/api/cyber/topup', [
            'sim_no' => $simNo,
            'amount' => $amount,
            'idempotency_key' => $key,
        ]);
    }

    // ── Commission accrual ───────────────────────────────────────

    public function test_completed_topup_accrues_commission_at_default_percent(): void
    {
        $agent = $this->agent();
        $subscriber = $this->subscriber();
        Sanctum::actingAs($agent);

        $this->topup('c-1', 1500)->assertOk();

        $commission = CyberAgentCommission::first();
        $this->assertNotNull($commission);
        $this->assertSame($agent->id, (int) $commission->agent_id);
        $this->assertSame($subscriber->id, (int) $commission->subscriber_id);
        $this->assertSame('1500.00', (string) $commission->topup_amount);
        $this->assertSame('5.00', (string) $commission->percent);
        $this->assertSame('75.00', (string) $commission->amount);
        $this->assertSame('accrued', $commission->status);
    }

    public function test_commission_percent_is_configurable(): void
    {
        config(['cyber.agent_commission_percent' => 10]);
        $this->subscriber();
        Sanctum::actingAs($this->agent());

        $this->topup('c-2', 500)->assertOk();

        $commission = CyberAgentCommission::first();
        $this->assertSame('10.00', (string) $commission->percent);
        $this->assertSame('50.00', (string) $commission->amount);
    }

    public function test_idempotent_retry_does_not_double_credit_commission(): void
    {
        $this->subscriber();
        Sanctum::actingAs($this->agent());

        $this->topup('c-3', 800)->assertOk()->assertJsonPath('data.duplicate', false);
        $this->topup('c-3', 800)->assertOk()->assertJsonPath('data.duplicate', true);

        $this->assertSame(1, CyberTopup::count());
        $this->assertSame(1, CyberAgentCommission::count());
    }

    public function test_reconcile_backfills_commission_for_topups_that_missed_the_event(): void
    {
        $agent = $this->agent();
        $subscriber = $this->subscriber();
        Sanctum::actingAs($agent);

        // A top-up row written outside the event flow (e.g. listener
        // not registered under route:cache) has no commission yet.
        CyberTopup::create([
            'agent_id' => $agent->id,
            'subscriber_id' => $subscriber->id,
            'sim_no' => '741234567',
            'amount' => 2000,
            'currency' => 'YER',
            'status' => 'completed',
            'idempotency_key' => 'orphan-1',
        ]);
        $this->assertSame(0, CyberAgentCommission::count());

        $this->getJson('/api/cyber/agent/earnings')->assertOk();

        $commission = CyberAgentCommission::first();
        $this->assertNotNull($commission);
        $this->assertSame('100.00', (string) $commission->amount); // 5% of 2000
    }

    // ── Agent endpoints ──────────────────────────────────────────

    public function test_earnings_returns_summary_and_ledger_for_this_agent_only(): void
    {
        $this->subscriber();
        $mine = $this->agent();
        $other = $this->agent();

        Sanctum::actingAs($mine);
        $this->topup('c-4', 1000)->assertOk();
        $this->topup('c-5', 500)->assertOk();

        Sanctum::actingAs($other);
        $this->topup('c-6', 3000)->assertOk();

        Sanctum::actingAs($mine);
        $response = $this->getJson('/api/cyber/agent/earnings')->assertOk();

        $summary = $response->json('data.summary');
        $this->assertEquals('75', $summary['accrued']);  // 50 + 25
        $this->assertSame(2, $summary['count']);
        $this->assertEquals('1500', $summary['topup_volume']);

        $rows = collect($response->json('data.commissions.data'));
        $this->assertCount(2, $rows);
        $this->assertTrue($rows->every(fn ($r) => (int) $r['agent_id'] === $mine->id));
    }

    public function test_topups_endpoint_lists_my_operations(): void
    {
        $this->subscriber();
        $agent = $this->agent();
        Sanctum::actingAs($agent);

        $this->topup('t-1', 200)->assertOk();
        $this->topup('t-2', 300)->assertOk();

        $response = $this->getJson('/api/cyber/agent/topups')->assertOk();

        $rows = collect($response->json('data.data'));
        $this->assertCount(2, $rows);
        $this->assertEqualsCanonicalizing(
            [200.0, 300.0],
            $rows->pluck('amount')->map(fn ($a) => (float) $a)->all()
        );
    }

    public function test_profile_exposes_agent_identity_and_commission_percent(): void
    {
        $agent = $this->agent();
        Sanctum::actingAs($agent);

        $response = $this->getJson('/api/cyber/agent/profile')->assertOk();

        $this->assertSame($agent->id, $response->json('data.agent_id'));
        $this->assertEquals(5.0, $response->json('data.commission_percent'));
    }

    public function test_agent_endpoints_require_auth(): void
    {
        $this->getJson('/api/cyber/agent/profile')->assertUnauthorized();
        $this->getJson('/api/cyber/agent/earnings')->assertUnauthorized();
        $this->getJson('/api/cyber/agent/topups')->assertUnauthorized();
    }
}
