<?php

namespace Tests\Feature;

use App\Models\CyberCreditEvent;
use App\Models\CyberCreditLimit;
use App\Models\CyberIdentity;
use App\Models\CyberSubscriber;
use App\Models\CyberTransfer;
use App\Models\CyberWallet;
use App\Models\User;
use App\Services\NotificationService;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * CYB-06 — subscriber→subscriber transfer + «سلفني» over the real
 * HTTP stack: atomic debit/credit with device-bound sender auth,
 * per-subscriber credit limits, automatic debt collection from the
 * next incoming top-up/transfer, and full idempotency.
 *
 * Self-contained like the CYB-04 suite: builds the minimal platform
 * tables it reads, then runs the real 2026_11_02_0000* cyber
 * migrations (which now include this sprint's three tables).
 */
class CyberTransferTest extends TestCase
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
        string $simNo,
        ?string $deviceId = null,
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

    private function balance(CyberSubscriber $subscriber): string
    {
        return (string) CyberWallet::where('subscriber_id', $subscriber->id)->value('balance');
    }

    // ── Transfer ─────────────────────────────────────────────────

    public function test_transfer_moves_balance_and_notifies_both_parties(): void
    {
        $sender = $this->subscriber('741234567', 'dev-1', 'fcm-sender');
        $recipient = $this->subscriber('749876543', 'dev-2', 'fcm-recipient');
        $this->fund($sender, 1000);
        $this->fund($recipient, 50);
        $notifier = $this->spy(NotificationService::class);

        $response = $this->postJson('/api/cyber/transfer', [
            'sim_no' => '741234567',
            'device_id' => 'dev-1',
            'to_sim_no' => '749876543',
            'amount' => 300,
            'idempotency_key' => 'tr-1',
        ]);

        $response->assertOk()->assertJsonPath('success', true)
            ->assertJsonPath('data.duplicate', false);
        $this->assertSame('700.00', $this->balance($sender));
        $this->assertSame('350.00', $this->balance($recipient));
        $this->assertDatabaseHas('cyber_transfers', [
            'from_sim_no' => '741234567', 'to_sim_no' => '749876543',
            'amount' => 300, 'status' => 'completed',
        ]);

        $notifier->shouldHaveReceived('sendToTokens')
            ->withArgs(fn (array $tokens, string $title, string $body) =>
                $tokens === ['fcm-recipient']
                    && str_contains($body, 'حوّل لك 741234567')
                    && str_contains($body, '300'))
            ->once();
        $notifier->shouldHaveReceived('sendToTokens')
            ->withArgs(fn (array $tokens, string $title, string $body) =>
                $tokens === ['fcm-sender']
                    && str_contains($body, '749876543'))
            ->once();
    }

    public function test_transfer_to_self_is_rejected(): void
    {
        $sender = $this->subscriber('741234567', 'dev-1');
        $this->fund($sender, 1000);

        $this->postJson('/api/cyber/transfer', [
            'sim_no' => '741234567',
            'device_id' => 'dev-1',
            'to_sim_no' => '741234567',
            'amount' => 100,
            'idempotency_key' => 'tr-self',
        ])->assertUnprocessable();

        $this->assertSame('1000.00', $this->balance($sender));
        $this->assertSame(0, CyberTransfer::count());
    }

    public function test_transfer_fails_on_insufficient_balance(): void
    {
        $sender = $this->subscriber('741234567', 'dev-1');
        $recipient = $this->subscriber('749876543', 'dev-2');
        $this->fund($sender, 100);
        $this->fund($recipient, 50);

        $this->postJson('/api/cyber/transfer', [
            'sim_no' => '741234567',
            'device_id' => 'dev-1',
            'to_sim_no' => '749876543',
            'amount' => 500,
            'idempotency_key' => 'tr-poor',
        ])->assertUnprocessable();

        $this->assertSame('100.00', $this->balance($sender));
        $this->assertSame('50.00', $this->balance($recipient));
        $this->assertSame(0, CyberTransfer::count());
    }

    public function test_transfer_same_idempotency_key_does_not_double(): void
    {
        $sender = $this->subscriber('741234567', 'dev-1');
        $recipient = $this->subscriber('749876543');
        $this->fund($sender, 1000);
        $this->fund($recipient, 0);

        $payload = [
            'sim_no' => '741234567',
            'device_id' => 'dev-1',
            'to_sim_no' => '749876543',
            'amount' => 300,
            'idempotency_key' => 'tr-same',
        ];
        $first = $this->postJson('/api/cyber/transfer', $payload)->assertOk();
        $second = $this->postJson('/api/cyber/transfer', $payload)->assertOk();

        $this->assertSame('700.00', $this->balance($sender));
        $this->assertSame('300.00', $this->balance($recipient));
        $this->assertSame(1, CyberTransfer::where('idempotency_key', 'tr-same')->count());
        $this->assertFalse($first->json('data.duplicate'));
        $this->assertTrue($second->json('data.duplicate'));
    }

    public function test_transfer_to_unknown_sim_returns_404(): void
    {
        $sender = $this->subscriber('741234567', 'dev-1');
        $this->fund($sender, 1000);

        $this->postJson('/api/cyber/transfer', [
            'sim_no' => '741234567',
            'device_id' => 'dev-1',
            'to_sim_no' => '749999999',
            'amount' => 100,
            'idempotency_key' => 'tr-404',
        ])->assertNotFound();

        $this->assertSame('1000.00', $this->balance($sender));
    }

    public function test_transfer_requires_bound_device(): void
    {
        $sender = $this->subscriber('741234567', 'dev-1');
        $this->subscriber('749876543');
        $this->fund($sender, 1000);

        $this->postJson('/api/cyber/transfer', [
            'sim_no' => '741234567',
            'device_id' => 'someone-elses-device',
            'to_sim_no' => '749876543',
            'amount' => 100,
            'idempotency_key' => 'tr-403',
        ])->assertForbidden();

        $this->assertSame('1000.00', $this->balance($sender));
    }

    // ── «سلفني» borrow ──────────────────────────────────────────

    public function test_borrow_adds_balance_and_notifies(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1', 'fcm-1');
        $this->fund($subscriber, 100);
        $notifier = $this->spy(NotificationService::class);

        $response = $this->postJson('/api/cyber/borrow', [
            'sim_no' => '741234567',
            'device_id' => 'dev-1',
            'amount' => 200,
            'idempotency_key' => 'br-1',
        ]);

        $response->assertOk()
            ->assertJsonPath('data.borrowed', 200)
            ->assertJsonPath('data.outstanding', 200);
        $this->assertSame('300.00', $this->balance($subscriber));
        $this->assertDatabaseHas('cyber_credit_events', [
            'sim_no' => '741234567', 'type' => 'borrow', 'amount' => 200,
        ]);
        $this->assertSame('200.00', (string) CyberCreditLimit::where('subscriber_id', $subscriber->id)->value('outstanding'));

        $notifier->shouldHaveReceived('sendToTokens')
            ->withArgs(fn (array $tokens, string $title, string $body) =>
                $tokens === ['fcm-1'] && str_contains($body, 'سلفة'))
            ->once();
    }

    public function test_borrow_is_blocked_while_debt_is_outstanding(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1');
        $this->fund($subscriber, 0);

        $this->postJson('/api/cyber/borrow', [
            'sim_no' => '741234567', 'device_id' => 'dev-1',
            'amount' => 200, 'idempotency_key' => 'br-a',
        ])->assertOk();

        $this->postJson('/api/cyber/borrow', [
            'sim_no' => '741234567', 'device_id' => 'dev-1',
            'amount' => 100, 'idempotency_key' => 'br-b',
        ])->assertUnprocessable();

        $this->assertSame(1, CyberCreditEvent::where('type', 'borrow')->count());
    }

    public function test_borrow_respects_the_credit_limit(): void
    {
        config(['cyber.credit.default_limit' => 500]);
        $subscriber = $this->subscriber('741234567', 'dev-1');
        $this->fund($subscriber, 0);

        $this->postJson('/api/cyber/borrow', [
            'sim_no' => '741234567', 'device_id' => 'dev-1',
            'amount' => 600, 'idempotency_key' => 'br-over',
        ])->assertUnprocessable();

        $this->assertSame('0.00', $this->balance($subscriber));
        $this->assertSame(0, CyberCreditEvent::count());
    }

    public function test_borrow_same_idempotency_key_does_not_double(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1');
        $this->fund($subscriber, 0);

        $payload = [
            'sim_no' => '741234567', 'device_id' => 'dev-1',
            'amount' => 200, 'idempotency_key' => 'br-same',
        ];
        $first = $this->postJson('/api/cyber/borrow', $payload)->assertOk();
        $second = $this->postJson('/api/cyber/borrow', $payload)->assertOk();

        $this->assertSame('200.00', $this->balance($subscriber));
        $this->assertSame(1, CyberCreditEvent::where('idempotency_key', 'br-same')->count());
        $this->assertFalse($first->json('data.duplicate'));
        $this->assertTrue($second->json('data.duplicate'));
    }

    // ── Automatic debt collection ────────────────────────────────

    public function test_debt_is_collected_from_the_next_topup(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1');
        $this->fund($subscriber, 0);

        $this->postJson('/api/cyber/borrow', [
            'sim_no' => '741234567', 'device_id' => 'dev-1',
            'amount' => 200, 'idempotency_key' => 'br-c',
        ])->assertOk();
        $this->assertSame('200.00', $this->balance($subscriber));

        Sanctum::actingAs(User::factory()->create(['type' => 'client']));
        $this->postJson('/api/cyber/topup', [
            'sim_no' => '741234567', 'amount' => 500, 'idempotency_key' => 'top-c',
        ])->assertOk();

        // 200 borrowed + 500 top-up − 200 collected = 500 net.
        $this->assertSame('500.00', $this->balance($subscriber));
        $this->assertSame('0.00', (string) CyberCreditLimit::where('subscriber_id', $subscriber->id)->value('outstanding'));
        $this->assertDatabaseHas('cyber_credit_events', [
            'type' => 'repay', 'amount' => 200, 'outstanding_after' => 0,
        ]);
    }

    public function test_debt_is_collected_from_an_incoming_transfer(): void
    {
        $recipient = $this->subscriber('749876543', 'dev-2');
        $sender = $this->subscriber('741234567', 'dev-1');
        $this->fund($recipient, 0);
        $this->fund($sender, 1000);

        $this->postJson('/api/cyber/borrow', [
            'sim_no' => '749876543', 'device_id' => 'dev-2',
            'amount' => 200, 'idempotency_key' => 'br-d',
        ])->assertOk();
        $this->assertSame('200.00', $this->balance($recipient));

        $this->postJson('/api/cyber/transfer', [
            'sim_no' => '741234567', 'device_id' => 'dev-1',
            'to_sim_no' => '749876543', 'amount' => 500,
            'idempotency_key' => 'tr-d',
        ])->assertOk()->assertJsonPath('data.debt_collected', 200);

        // 200 borrowed + 500 transfer − 200 collected = 500 net.
        $this->assertSame('500.00', $this->balance($recipient));
        $this->assertSame('500.00', $this->balance($sender));
        $this->assertSame('0.00', (string) CyberCreditLimit::where('subscriber_id', $recipient->id)->value('outstanding'));
    }

    public function test_partial_collection_when_credit_is_less_than_debt(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1');
        $this->fund($subscriber, 0);

        $this->postJson('/api/cyber/borrow', [
            'sim_no' => '741234567', 'device_id' => 'dev-1',
            'amount' => 400, 'idempotency_key' => 'br-e',
        ])->assertOk();

        // The borrowed balance was spent (e.g. on a package) — only
        // the new top-up is available to collect against.
        CyberWallet::where('subscriber_id', $subscriber->id)->update(['balance' => 0]);

        Sanctum::actingAs(User::factory()->create(['type' => 'client']));
        $this->postJson('/api/cyber/topup', [
            'sim_no' => '741234567', 'amount' => 150, 'idempotency_key' => 'top-e',
        ])->assertOk();

        // 0 + 150 − 150 collected = 0 left; 250 still owed.
        $this->assertSame('0.00', $this->balance($subscriber));
        $this->assertSame('250.00', (string) CyberCreditLimit::where('subscriber_id', $subscriber->id)->value('outstanding'));
    }

    public function test_credit_status_endpoint_reports_position(): void
    {
        $subscriber = $this->subscriber('741234567', 'dev-1');
        $this->fund($subscriber, 0);

        $this->getJson('/api/cyber/credit?sim_no=741234567&device_id=dev-1')
            ->assertOk()
            ->assertJsonPath('data.limit', 500)
            ->assertJsonPath('data.outstanding', 0)
            ->assertJsonPath('data.can_borrow', true);

        $this->postJson('/api/cyber/borrow', [
            'sim_no' => '741234567', 'device_id' => 'dev-1',
            'amount' => 200, 'idempotency_key' => 'br-f',
        ])->assertOk();

        $this->getJson('/api/cyber/credit?sim_no=741234567&device_id=dev-1')
            ->assertOk()
            ->assertJsonPath('data.outstanding', 200)
            ->assertJsonPath('data.can_borrow', false);
    }
}
