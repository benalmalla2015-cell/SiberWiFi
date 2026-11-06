<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccPosDevice;
use App\Models\AccPosPoint;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-03 — the three operating roles (PLAN §1) over the real HTTP
 * stack: EnsureAccountingContext resolves the tenant, per-route
 * acc:{permission} checks gate each role, and every query is
 * tenant-scoped.
 *
 * Self-contained like AccPostingServiceTest: builds a minimal
 * users/networks schema plus the acc_* migrations it needs.
 */
class AccAgentsPosTest extends TestCase
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
                $t->softDeletes(); // Network model uses SoftDeletes
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
            foreach ([
                database_path('migrations/2026_10_26_010005_create_acc_audit_log_table.php'),
                ...glob(database_path('migrations/2026_10_27_0200*_create_acc_*.php')) ?: [],
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

    private function person(string $phone): User
    {
        return User::factory()->create([
            'type' => 'customer',
            'phone' => $phone,
            'is_active' => true,
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

    // ── Session / role resolution ────────────────────────────────

    public function test_owner_gets_owner_role_and_full_permissions(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $res = $this->getJson(self::BASE . '/me');
        $res->assertOk()->assertJsonPath('data.role', 'owner')
            ->assertJsonPath('data.owner_id', $owner->id)
            ->assertJsonPath('data.agent', null);
        $this->assertContains('*', $res->json('data.permissions'));
    }

    public function test_each_agent_role_logs_in_and_resolves_its_role(): void
    {
        $owner = $this->owner();
        foreach (['admin', 'distributor', 'pos'] as $i => $role) {
            $user = $this->person("77100000{$i}");
            $agent = $this->makeAgent($owner, $user, $role);

            Sanctum::actingAs($user);
            $res = $this->getJson(self::BASE . '/me');

            $res->assertOk()
                ->assertJsonPath('data.role', $role)
                ->assertJsonPath('data.owner_id', $owner->id)
                ->assertJsonPath('data.agent.id', $agent->id);
        }
    }

    public function test_plain_customer_without_agent_row_is_rejected(): void
    {
        Sanctum::actingAs($this->person('779999999'));
        $this->getJson(self::BASE . '/me')
            ->assertForbidden()
            ->assertJsonPath('code', 'no_accounting_account');
    }

    public function test_suspended_agent_loses_access(): void
    {
        $owner = $this->owner();
        $user = $this->person('771111111');
        $this->makeAgent($owner, $user, 'distributor', ['status' => 'suspended']);

        Sanctum::actingAs($user);
        $this->getJson(self::BASE . '/me')->assertForbidden();
    }

    public function test_guest_is_unauthenticated(): void
    {
        $this->getJson(self::BASE . '/me')->assertUnauthorized();
    }

    // ── Agents CRUD + permission gating ─────────────────────────

    public function test_owner_creates_agent_by_phone_lookup(): void
    {
        $owner = $this->owner();
        $user = $this->person('967772222222');
        Sanctum::actingAs($owner);

        $res = $this->postJson(self::BASE . '/agents', [
            'phone' => '772222222', // normalized variant should match
            'display_name' => 'أحمد الموزع',
            'role' => 'distributor',
            'cash_allowed' => true,
            'credit_allowed' => true,
            'daily_limit_per_category' => '{"3": 50}',
        ]);

        $res->assertCreated()->assertJsonPath('data.role', 'distributor');
        $agent = AccAgent::sole();
        $this->assertSame($user->id, $agent->user_id);
        $this->assertSame($owner->id, $agent->network_owner_id);
        $this->assertEquals(['3' => 50], $agent->daily_limit_per_category);
        $this->assertTrue($agent->cash_allowed && $agent->credit_allowed);
    }

    public function test_admin_agent_can_manage_agents_but_pos_cannot(): void
    {
        $owner = $this->owner();
        $adminUser = $this->person('773333331');
        $posUser = $this->person('773333332');
        $this->makeAgent($owner, $adminUser, 'admin');
        $this->makeAgent($owner, $posUser, 'pos');
        $target = $this->person('773333333');

        Sanctum::actingAs($adminUser);
        $this->getJson(self::BASE . '/agents')->assertOk();
        $this->postJson(self::BASE . '/agents', [
            'phone' => $target->phone,
            'display_name' => 'وكيل جديد',
            'role' => 'pos',
        ])->assertCreated();

        Sanctum::actingAs($posUser);
        $this->getJson(self::BASE . '/agents')->assertForbidden();
        $this->postJson(self::BASE . '/agents', [
            'phone' => '700000000',
            'display_name' => 'x',
            'role' => 'admin',
        ])->assertForbidden();
    }

    public function test_agent_creation_validations(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        // Unknown phone.
        $this->postJson(self::BASE . '/agents', [
            'phone' => '700000001', 'display_name' => 'x', 'role' => 'pos',
        ])->assertUnprocessable();

        // Owner's own account cannot become an agent.
        $this->postJson(self::BASE . '/agents', [
            'phone' => $owner->phone, 'display_name' => 'x', 'role' => 'admin',
        ])->assertUnprocessable();

        // Same user cannot be enrolled twice.
        $user = $this->person('774444441');
        $this->postJson(self::BASE . '/agents', [
            'phone' => $user->phone, 'display_name' => 'أ', 'role' => 'pos',
        ])->assertCreated();
        $this->postJson(self::BASE . '/agents', [
            'phone' => $user->phone, 'display_name' => 'ب', 'role' => 'admin',
        ])->assertUnprocessable();

        $this->assertSame(1, AccAgent::count());
    }

    public function test_agent_update_and_suspend(): void
    {
        $owner = $this->owner();
        $user = $this->person('775555551');
        $agent = $this->makeAgent($owner, $user, 'distributor');
        Sanctum::actingAs($owner);

        $this->putJson(self::BASE . "/agents/{$agent->id}", [
            'status' => 'suspended',
            'commission_mode' => 'percent',
            'commission_value' => 5,
        ])->assertOk()->assertJsonPath('data.status', 'suspended');

        // Suspended agent immediately loses API access.
        Sanctum::actingAs($user);
        $this->getJson(self::BASE . '/me')->assertForbidden();
    }

    // ── POS points + devices ─────────────────────────────────────

    public function test_pos_point_lifecycle_with_pos_agent_binding(): void
    {
        $owner = $this->owner();
        $posUser = $this->person('776666661');
        $distUser = $this->person('776666662');
        $posAgent = $this->makeAgent($owner, $posUser, 'pos');
        $distAgent = $this->makeAgent($owner, $distUser, 'distributor');
        Sanctum::actingAs($owner);

        // Distributor agent can't operate a POS point.
        $this->postJson(self::BASE . '/pos', [
            'name' => 'بقالة النور', 'agent_id' => $distAgent->id,
        ])->assertUnprocessable();

        $res = $this->postJson(self::BASE . '/pos', [
            'name' => 'بقالة النور',
            'location' => 'شارع الستين',
            'owner_name' => 'محمد',
            'phone' => '770123456',
            'agent_id' => $posAgent->id,
            'credit_limit' => 50000,
        ]);
        $res->assertCreated()->assertJsonPath('data.agent_id', $posAgent->id);

        $point = AccPosPoint::sole();
        $this->assertSame($owner->id, $point->network_owner_id);

        // Suspend the outlet.
        $this->putJson(self::BASE . "/pos/{$point->id}", ['status' => 'suspended'])
            ->assertOk()->assertJsonPath('data.status', 'suspended');
    }

    public function test_distributor_reads_pos_but_cannot_manage(): void
    {
        $owner = $this->owner();
        $distUser = $this->person('777777771');
        $this->makeAgent($owner, $distUser, 'distributor');
        AccPosPoint::create([
            'network_owner_id' => $owner->id,
            'name' => 'نقطة', 'status' => 'active',
        ]);

        Sanctum::actingAs($distUser);
        $this->getJson(self::BASE . '/pos')
            ->assertOk()
            ->assertJsonCount(1, 'data.data');
        $this->postJson(self::BASE . '/pos', ['name' => 'x'])->assertForbidden();
    }

    public function test_device_binding_and_uid_uniqueness(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);
        $point = AccPosPoint::create([
            'network_owner_id' => $owner->id,
            'name' => 'نقطة', 'status' => 'active',
        ]);

        $this->postJson(self::BASE . "/pos/{$point->id}/devices", [
            'device_uid' => 'dev-abc',
            'device_name' => 'هاتف الكاشير',
            'model' => 'Samsung A52',
        ])->assertCreated();

        // Same uid under the same owner is rejected.
        $this->postJson(self::BASE . "/pos/{$point->id}/devices", [
            'device_uid' => 'dev-abc',
            'device_name' => 'جهاز آخر',
        ])->assertUnprocessable();

        $this->getJson(self::BASE . "/pos/{$point->id}/devices")
            ->assertOk()->assertJsonCount(1, 'data');

        $device = AccPosDevice::sole();
        $this->assertNotNull($device->bound_at);

        $this->deleteJson(self::BASE . "/pos/{$point->id}/devices/{$device->id}")
            ->assertOk();
        $this->assertSame(0, AccPosDevice::count());
    }

    // ── Tenant isolation ─────────────────────────────────────────

    public function test_tenant_isolation_between_owners(): void
    {
        $ownerA = $this->owner('770000001');
        $ownerB = $this->owner('770000002');
        $userB = $this->person('778888881');
        $agentB = $this->makeAgent($ownerB, $userB, 'admin');

        $agentA = $this->makeAgent($ownerA, $this->person('778888882'), 'pos');
        $pointA = AccPosPoint::create([
            'network_owner_id' => $ownerA->id, 'name' => 'نقطة أ', 'status' => 'active',
        ]);

        Sanctum::actingAs($userB);
        // B sees only their own tenant.
        $this->getJson(self::BASE . '/agents')->assertOk()
            ->assertJsonCount(1, 'data.data')
            ->assertJsonPath('data.data.0.id', $agentB->id);
        $this->getJson(self::BASE . '/pos')->assertOk()
            ->assertJsonCount(0, 'data.data');
        // A's point is invisible/unwritable to B.
        $this->putJson(self::BASE . "/pos/{$pointA->id}", ['name' => 'مخترق'])
            ->assertNotFound();
        $this->deleteJson(self::BASE . "/agents/{$agentA->id}")->assertNotFound();
    }
}
