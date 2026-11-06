<?php

namespace Tests\Feature;

use App\Models\AccAgent;
use App\Models\AccBackup;
use App\Models\AccCardCategory;
use App\Models\AccCashBox;
use App\Models\AccCollection;
use App\Models\AccJournalEntry;
use App\Models\AccPosOrder;
use App\Models\AccPosPoint;
use App\Models\AccSyncQueue;
use App\Models\User;
use App\Services\AccContext;
use App\Services\AccMoneyService;
use App\Services\AccPostingService;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * ACC-12 — the offline sync queue + backups + doc header over the
 * real HTTP stack:
 *
 * - POST /sync/push replays offline ops through their domain
 *   services (balanced journal + rows), keyed by client_op_id so
 *   re-pushing is a free replay.
 * - Failed ops park as needs_review → retry / discard.
 * - AccPostingService's failure hook writes post:* needs_review
 *   rows into the same queue.
 * - acc_backups export → checksum-verified file → atomic restore.
 * - acc_doc_header settings roundtrip (+ private logo).
 *
 * Self-contained like the other acc suites: builds the ACC-01..05
 * schema plus this sprint's 1200* migrations.
 */
class AccSyncBackupTest extends TestCase
{
    private const BASE = '/api/network-owner/accounting';

    protected function setUp(): void
    {
        parent::setUp();
        $this->createSchema();
        Storage::fake('local');
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
        if (! Schema::hasTable('card_categories')) {
            Schema::create('card_categories', function (Blueprint $t) {
                $t->id();
                $t->foreignId('network_id');
                $t->string('name');
                $t->decimal('price', 12, 2)->default(0);
                $t->timestamps();
            });
        }
        if (! Schema::hasTable('acc_journal_entries')) {
            foreach (
                glob(database_path('migrations/2026_10_26_0100*_create_acc_*.php')) ?: []
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
        if (! Schema::hasTable('acc_card_categories')) {
            foreach (
                glob(database_path('migrations/2026_10_27_0300*_create_acc_*.php')) ?: []
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
        if (! Schema::hasTable('acc_cash_boxes')) {
            foreach (
                glob(database_path('migrations/2026_10_27_0500*_create_acc_*.php')) ?: []
                as $file
            ) {
                (require $file)->up();
            }
        }
        if (! Schema::hasTable('acc_sync_queue')) {
            foreach (
                glob(database_path('migrations/2026_10_29_1200*_create_acc_*.php')) ?: []
                as $file
            ) {
                (require $file)->up();
            }
        }
        if (! Schema::hasTable('exchange_rate_settings')) {
            Schema::create('exchange_rate_settings', function (Blueprint $t) {
                $t->id();
                $t->enum('base_currency', ['north', 'south'])->default('north');
                $t->decimal('rate_percent', 10, 4)->default(100);
                $t->text('description')->nullable();
                $t->boolean('is_active')->default(true);
                $t->timestamps();
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

    private function box(User $owner, string $name = 'الرئيسي', float $balance = 0): AccCashBox
    {
        return app(AccMoneyService::class)->createBox(
            AccContext::forUser($owner),
            ['name' => $name, 'currency' => 'north', 'opening_balance' => $balance]
        );
    }

    private function pushOps(array $ops): \Illuminate\Testing\TestResponse
    {
        return $this->postJson(self::BASE . '/sync/push', ['ops' => $ops]);
    }

    private function collectionOp(string $id, array $payload): array
    {
        return [
            'client_op_id' => $id,
            'op_type' => 'collection.create',
            'payload' => $payload,
            'queued_at' => '2026-10-29 10:00:00',
        ];
    }

    // ── Push path ────────────────────────────────────────────────

    public function test_offline_collection_posts_balanced_entry_on_sync(): void
    {
        $owner = $this->owner();
        $box = $this->box($owner, 'الرئيسي', 1000);
        Sanctum::actingAs($owner);

        $res = $this->pushOps([
            $this->collectionOp('op-1', [
                'party_type' => 'person',
                'party_name' => 'زبون نقدي',
                'amount' => 5000,
                'cash_box_id' => $box->id,
            ]),
        ]);

        $res->assertOk()
            ->assertJsonPath('results.0.client_op_id', 'op-1')
            ->assertJsonPath('results.0.status', 'sent');

        $collection = AccCollection::sole();
        $this->assertSame(5000.0, (float) $collection->amount);
        // queued_at back-fills the real collection moment.
        $this->assertSame('2026-10-29', $collection->collected_at?->toDateString()
            ?? substr((string) $collection->collected_at, 0, 10));

        $entry = AccJournalEntry::where('doc_type', 'collection')->sole();
        $this->assertSame(
            (float) $entry->lines->sum('debit'),
            (float) $entry->lines->sum('credit')
        );
        $this->assertSame(6000.0, (float) $box->fresh()->balance);

        $row = AccSyncQueue::sole();
        $this->assertSame('sent', $row->status);
        $this->assertSame($collection->id, (int) $row->result['ref_id']);
        $this->assertNotNull($row->sent_at);
    }

    public function test_repush_same_client_op_id_is_replay_not_duplicate(): void
    {
        $owner = $this->owner();
        $box = $this->box($owner);
        Sanctum::actingAs($owner);

        $op = $this->collectionOp('op-dup', [
            'party_type' => 'person', 'party_name' => 'زبون',
            'amount' => 700, 'cash_box_id' => $box->id,
        ]);
        $this->pushOps([$op])->assertOk()->assertJsonPath('results.0.status', 'sent');
        $this->pushOps([$op])->assertOk()->assertJsonPath('results.0.status', 'replayed');

        $this->assertSame(1, AccCollection::count());
        $this->assertSame(1, AccSyncQueue::count());
    }

    public function test_failed_op_parks_needs_review_then_retry_sends(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        // Box 77 does not exist yet — the op must park, not vanish.
        $this->pushOps([
            $this->collectionOp('op-late', [
                'party_type' => 'person', 'party_name' => 'زبون',
                'amount' => 300, 'cash_box_id' => 77,
            ]),
        ])->assertJsonPath('results.0.status', 'needs_review');

        $row = AccSyncQueue::sole();
        $this->assertSame('needs_review', $row->status);
        $this->assertNotEmpty($row->last_error);

        // Fix the world, then the sync center retry succeeds.
        $box = $this->box($owner);
        $row->payload = array_merge($row->payload, [
            'data' => array_merge($row->payload['data'], ['cash_box_id' => $box->id]),
        ]);
        $row->save();

        $this->postJson(self::BASE . "/sync/{$row->id}/retry")
            ->assertOk()->assertJsonPath('result.status', 'sent');

        $this->assertSame('sent', $row->fresh()->status);
        $this->assertSame(1, AccCollection::count());
        $this->assertSame(300.0, (float) $box->fresh()->balance);
    }

    public function test_discard_drops_stuck_op(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $this->pushOps([
            ['client_op_id' => 'op-bad', 'op_type' => 'nonsense.op', 'payload' => []],
        ]);
        $row = AccSyncQueue::sole();
        $this->assertSame('needs_review', $row->status);

        $this->postJson(self::BASE . "/sync/{$row->id}/discard")
            ->assertOk()->assertJsonPath('counts.needs_review', 0);
        $this->assertSame(0, AccSyncQueue::count());
    }

    public function test_posting_failure_hook_writes_needs_review_row(): void
    {
        $owner = $this->owner();

        try {
            app(AccPostingService::class)->post('adjustment', [
                'network_owner_id' => $owner->id,
                'lines' => [
                    ['account_code' => 'no_such_account', 'debit' => 100],
                    ['account_code' => 'also_missing', 'credit' => 100],
                ],
            ]);
            $this->fail('post should have thrown');
        } catch (\Throwable) {
        }

        $row = AccSyncQueue::sole();
        $this->assertSame('needs_review', $row->status);
        $this->assertSame('post:adjustment', $row->op_type);
        $this->assertNull($row->client_op_id);
    }

    public function test_pending_endpoint_reports_counts_and_attention_list(): void
    {
        $owner = $this->owner();
        $box = $this->box($owner);
        Sanctum::actingAs($owner);

        $this->pushOps([
            $this->collectionOp('ok', [
                'party_type' => 'person', 'party_name' => 'زبون',
                'amount' => 10, 'cash_box_id' => $box->id,
            ]),
            ['client_op_id' => 'bad', 'op_type' => 'nonsense.op', 'payload' => []],
        ]);

        $res = $this->getJson(self::BASE . '/sync/pending');
        $res->assertOk()
            ->assertJsonPath('counts.sent', 1)
            ->assertJsonPath('counts.needs_review', 1)
            ->assertJsonCount(1, 'data');
    }

    public function test_pos_agent_pushes_order_for_own_point(): void
    {
        $owner = $this->owner();
        $posUser = User::factory()->create([
            'type' => 'customer', 'phone' => '770000077', 'is_active' => true,
        ]);
        $agent = AccAgent::create([
            'network_owner_id' => $owner->id, 'user_id' => $posUser->id,
            'role' => 'pos', 'display_name' => 'بقالة', 'status' => 'active',
        ]);
        $pos = AccPosPoint::create([
            'network_owner_id' => $owner->id, 'agent_id' => $agent->id,
            'name' => 'بقالة النور', 'status' => 'active',
        ]);
        $cat = AccCardCategory::create([
            'network_owner_id' => $owner->id, 'name' => 'باقة',
            'sell_price' => 200, 'cost_price' => 100, 'is_active' => true,
        ]);

        Sanctum::actingAs($posUser);
        $this->pushOps([[
            'client_op_id' => 'pos-1',
            'op_type' => 'pos.order',
            'payload' => ['items' => [['category_id' => $cat->id, 'qty' => 3]]],
        ]])->assertJsonPath('results.0.status', 'sent');

        $order = AccPosOrder::sole();
        $this->assertSame($pos->id, $order->pos_id);
        $this->assertSame(3, (int) $order->items->sum('qty'));
    }

    // ── Backups ──────────────────────────────────────────────────

    public function test_backup_export_registers_snapshot_then_restore_reverts(): void
    {
        $owner = $this->owner();
        $box = $this->box($owner, 'الرئيسي', 1000);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'person', 'party_name' => 'زبون',
            'amount' => 500, 'cash_box_id' => $box->id,
        ])->assertCreated();

        $entriesAtBackup = AccJournalEntry::count();

        $res = $this->postJson(self::BASE . '/backup');
        $res->assertCreated();
        $this->assertGreaterThan(0, (int) $res->json('data.tables_count'));
        $this->assertGreaterThan(0, (int) $res->json('data.rows_count'));

        $backup = AccBackup::sole();
        $this->assertTrue($backup->fileExists());

        $raw = Storage::disk('local')->get($backup->storagePath());
        $payload = json_decode($raw, true);
        $this->assertSame('saiber-acc-backup', $payload['signature']);
        $this->assertSame(
            hash('sha256', json_encode($payload['tables'], JSON_UNESCAPED_UNICODE)),
            $payload['checksum']
        );

        // Mutate state after the snapshot.
        $this->postJson(self::BASE . '/collections', [
            'party_type' => 'person', 'party_name' => 'زبون',
            'amount' => 900, 'cash_box_id' => $box->id,
        ])->assertCreated();
        $this->box($owner, 'إضافي', 50);
        $this->assertGreaterThan($entriesAtBackup, AccJournalEntry::count());

        // Restore reverts everything to the snapshot — atomically.
        $this->postJson(self::BASE . "/backups/{$backup->id}/restore")->assertOk();

        $this->assertSame(1, AccCollection::count());
        $this->assertSame(1, AccCashBox::count());
        $this->assertSame($entriesAtBackup, AccJournalEntry::count());
        $this->assertSame(1500.0, (float) $box->fresh()->balance);
    }

    public function test_backup_download_and_import_roundtrip(): void
    {
        $owner = $this->owner();
        $this->box($owner);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/backup')->assertCreated();
        $backup = AccBackup::sole();

        $this->getJson(self::BASE . "/backups/{$backup->id}/download")
            ->assertOk();

        $path = Storage::disk('local')->path($backup->storagePath());
        $upload = new UploadedFile($path, 'snap.json', 'application/json', null, true);

        $this->postJson(self::BASE . '/backups/import', ['file' => $upload])
            ->assertCreated();
        $this->assertSame(2, AccBackup::count());
    }

    public function test_tampered_snapshot_is_rejected_before_restore(): void
    {
        $owner = $this->owner();
        $this->box($owner);
        Sanctum::actingAs($owner);

        $this->postJson(self::BASE . '/backup')->assertCreated();
        $backup = AccBackup::sole();

        $payload = json_decode(Storage::disk('local')->get($backup->storagePath()), true);
        $payload['tables']['acc_cash_boxes'][0]['balance'] = 999999;
        Storage::disk('local')->put($backup->storagePath(), json_encode($payload));

        $this->postJson(self::BASE . "/backups/{$backup->id}/restore")
            ->assertStatus(422);
    }

    // ── Doc header ───────────────────────────────────────────────

    public function test_doc_header_roundtrip_and_logo(): void
    {
        $owner = $this->owner();
        Sanctum::actingAs($owner);

        $this->getJson(self::BASE . '/doc-header')
            ->assertOk()->assertJsonPath('data.show_logo', true);

        $this->putJson(self::BASE . '/doc-header', [
            'business_name' => 'شبكة سايبر',
            'subtitle' => 'كروت إنترنت',
            'phone' => '770000001',
            'address' => 'عدن',
            'footer_text' => 'شكراً لتعاملكم',
            'show_logo' => false,
        ])->assertOk()->assertJsonPath('data.business_name', 'شبكة سايبر');

        $this->postJson(self::BASE . '/doc-header/logo', [
            'logo' => UploadedFile::fake()->image('logo.png', 64, 64),
        ])->assertOk()->assertJsonPath('data.has_logo', true);

        $this->getJson(self::BASE . '/doc-header/logo')->assertOk();

        $this->deleteJson(self::BASE . '/doc-header/logo')
            ->assertOk()->assertJsonPath('data.has_logo', false);
    }

    // ── Tenant isolation ─────────────────────────────────────────

    public function test_sync_queue_and_backups_are_tenant_scoped(): void
    {
        $ownerA = $this->owner('770000001');
        $ownerB = $this->owner('770000002');
        $this->box($ownerA);

        Sanctum::actingAs($ownerA);
        $this->pushOps([
            ['client_op_id' => 'a1', 'op_type' => 'nonsense.op', 'payload' => []],
        ]);
        $this->postJson(self::BASE . '/backup')->assertCreated();

        $opA = AccSyncQueue::sole();

        Sanctum::actingAs($ownerB);
        $this->getJson(self::BASE . '/sync/pending')
            ->assertOk()->assertJsonPath('counts.needs_review', 0);
        $this->postJson(self::BASE . "/sync/{$opA->id}/retry")->assertNotFound();
        $this->postJson(self::BASE . "/sync/{$opA->id}/discard")->assertNotFound();
        $this->getJson(self::BASE . '/backups')->assertOk()
            ->assertJsonCount(0, 'data.data');
    }
}
