<?php

namespace Tests\Feature;

use App\Models\AccAccount;
use App\Models\AccAuditLog;
use App\Models\AccBalance;
use App\Models\AccJournalEntry;
use App\Models\AccJournalLine;
use App\Models\User;
use App\Services\AccPostingException;
use App\Services\AccPostingService;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Self-contained: the repo's full migration set cannot run on sqlite
 * (a legacy wallet migration uses MySQL-only MODIFY COLUMN), so this
 * suite builds only the schema it needs — a minimal `users` table
 * plus the five acc_* tables, in dependency order.
 */
class AccPostingServiceTest extends TestCase
{
    private AccPostingService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createSchema();
        $this->service = app(AccPostingService::class);
    }

    private function createSchema(): void
    {
        if (! Schema::hasTable('users')) {
            Schema::create('users', function (Blueprint $t) {
                $t->id();
                $t->string('name');
                $t->string('email')->unique();
                $t->timestamp('email_verified_at')->nullable();
                $t->string('password');
                $t->rememberToken();
                $t->timestamps();
            });
        }

        if (! Schema::hasTable('acc_journal_entries')) {
            foreach (
                glob(database_path('migrations/2026_10_26_0100*_create_acc_*.php'))
                as $file
            ) {
                (require $file)->up();
            }
        }
    }

    private function postEntry(int $ownerId, array $overrides = []): AccJournalEntry
    {
        return $this->service->post('collection', array_merge([
            'network_owner_id' => $ownerId,
            'memo' => 'تحصيل من نقطة بيع',
            'lines' => [
                [
                    'account_code' => AccAccount::CASH_MAIN,
                    'party_type' => 'box', 'party_id' => 1,
                    'debit' => 500, 'credit' => 0,
                ],
                [
                    'account_code' => AccAccount::AR_POS,
                    'party_type' => 'pos', 'party_id' => 7,
                    'debit' => 0, 'credit' => 500,
                ],
            ],
        ], $overrides));
    }

    public function test_post_creates_posted_balanced_entry(): void
    {
        $owner = User::factory()->create();

        $entry = $this->postEntry($owner->id);

        $this->assertTrue($entry->is_posted);
        $this->assertNotNull($entry->posted_at);
        $this->assertMatchesRegularExpression('/^JE-\d{8}-\d{5}$/', $entry->entry_no);
        $this->assertSame('collection', $entry->doc_type);

        $lines = $entry->lines;
        $this->assertCount(2, $lines);
        $this->assertEquals(
            (float) $lines->sum('debit'),
            (float) $lines->sum('credit')
        );
    }

    public function test_default_chart_is_seeded_once_per_owner(): void
    {
        $owner = User::factory()->create();

        $this->postEntry($owner->id);
        $expected = count(AccAccount::defaultChart());
        $this->assertSame(
            $expected,
            AccAccount::where('network_owner_id', $owner->id)->count()
        );

        // Second post must not duplicate the chart.
        $this->postEntry($owner->id);
        $this->assertSame(
            $expected,
            AccAccount::where('network_owner_id', $owner->id)->count()
        );
    }

    public function test_unbalanced_entry_is_rejected_atomically(): void
    {
        $owner = User::factory()->create();

        try {
            $this->postEntry($owner->id, [
                'lines' => [
                    ['account_code' => AccAccount::CASH_MAIN, 'debit' => 500, 'credit' => 0],
                    ['account_code' => AccAccount::AR_POS, 'debit' => 0, 'credit' => 490],
                ],
            ]);
            $this->fail('Expected AccPostingException');
        } catch (AccPostingException $e) {
            $this->assertStringContainsString('غير متوازن', $e->getMessage());
        }

        $this->assertSame(0, AccJournalEntry::count());
        $this->assertSame(0, AccJournalLine::count());
        $this->assertSame(0, AccBalance::count());
        $this->assertSame(0, AccAuditLog::count());
    }

    public function test_idempotency_key_replays_the_same_entry(): void
    {
        $owner = User::factory()->create();

        $first = $this->postEntry($owner->id, ['idempotency_key' => 'coll-001']);
        $second = $this->postEntry($owner->id, ['idempotency_key' => 'coll-001']);

        $this->assertSame($first->id, $second->id);
        $this->assertSame(1, AccJournalEntry::count());
        $this->assertSame(2, AccJournalLine::count());
        $this->assertSame(1, AccAuditLog::count());
        // The balance was applied exactly once.
        $this->assertSame(500.0, $this->service->balanceOf($owner->id, 'box', 1));
    }

    public function test_party_balances_accumulate_atomically(): void
    {
        $owner = User::factory()->create();

        $this->postEntry($owner->id);
        $this->assertSame(500.0, $this->service->balanceOf($owner->id, 'box', 1));
        $this->assertSame(-500.0, $this->service->balanceOf($owner->id, 'pos', 7));

        $this->postEntry($owner->id);
        $this->assertSame(1000.0, $this->service->balanceOf($owner->id, 'box', 1));
        $this->assertSame(-1000.0, $this->service->balanceOf($owner->id, 'pos', 7));
    }

    public function test_balances_are_isolated_per_owner(): void
    {
        $ownerA = User::factory()->create();
        $ownerB = User::factory()->create();

        $this->postEntry($ownerA->id);
        $this->postEntry($ownerB->id);

        $this->assertSame(500.0, $this->service->balanceOf($ownerA->id, 'box', 1));
        $this->assertSame(500.0, $this->service->balanceOf($ownerB->id, 'box', 1));
        $this->assertSame(
            1,
            AccBalance::where('network_owner_id', $ownerA->id)
                ->where('party_type', 'box')->where('party_id', 1)->count()
        );
    }

    public function test_entry_numbers_are_sequential_per_day_per_owner(): void
    {
        $ownerA = User::factory()->create();
        $ownerB = User::factory()->create();

        $a1 = $this->postEntry($ownerA->id);
        $a2 = $this->postEntry($ownerA->id);
        $b1 = $this->postEntry($ownerB->id);

        $today = now()->format('Ymd');
        $this->assertSame("JE-{$today}-00001", $a1->entry_no);
        $this->assertSame("JE-{$today}-00002", $a2->entry_no);
        $this->assertSame("JE-{$today}-00001", $b1->entry_no);
    }

    public function test_audit_log_row_is_written_with_meta(): void
    {
        $owner = User::factory()->create();
        $agent = User::factory()->create();

        $entry = $this->postEntry($owner->id, ['agent_id' => $agent->id]);

        $log = AccAuditLog::sole();
        $this->assertSame($owner->id, $log->network_owner_id);
        $this->assertSame($agent->id, $log->agent_id);
        $this->assertSame('journal.post', $log->action);
        $this->assertSame('acc_journal_entries', $log->entity);
        $this->assertSame($entry->id, $log->entity_id);
        $this->assertArrayHasKey('latency_ms', $log->meta);
        $this->assertArrayHasKey('payload_hash', $log->meta);
    }

    public function test_malformed_lines_are_rejected(): void
    {
        $owner = User::factory()->create();
        $bad = [
            'single line' => [
                ['account_code' => AccAccount::CASH_MAIN, 'debit' => 100, 'credit' => 0],
            ],
            'zero line' => [
                ['account_code' => AccAccount::CASH_MAIN, 'debit' => 0, 'credit' => 0],
                ['account_code' => AccAccount::AR_POS, 'debit' => 0, 'credit' => 100],
            ],
            'both sides' => [
                ['account_code' => AccAccount::CASH_MAIN, 'debit' => 100, 'credit' => 50],
                ['account_code' => AccAccount::AR_POS, 'debit' => 0, 'credit' => 50],
            ],
            'negative' => [
                ['account_code' => AccAccount::CASH_MAIN, 'debit' => -100, 'credit' => 0],
                ['account_code' => AccAccount::AR_POS, 'debit' => 0, 'credit' => -100],
            ],
            'half party' => [
                ['account_code' => AccAccount::CASH_MAIN, 'party_type' => 'box', 'debit' => 100, 'credit' => 0],
                ['account_code' => AccAccount::AR_POS, 'debit' => 0, 'credit' => 100],
            ],
            'bad party type' => [
                ['account_code' => AccAccount::CASH_MAIN, 'party_type' => 'alien', 'party_id' => 1, 'debit' => 100, 'credit' => 0],
                ['account_code' => AccAccount::AR_POS, 'debit' => 0, 'credit' => 100],
            ],
        ];

        foreach ($bad as $case => $lines) {
            try {
                $this->postEntry($owner->id, ['lines' => $lines]);
                $this->fail("Case '{$case}' should have thrown");
            } catch (AccPostingException) {
                // expected
            }
        }

        $this->assertSame(0, AccJournalEntry::count());
    }

    public function test_unknown_account_code_is_rejected(): void
    {
        $owner = User::factory()->create();

        $this->expectException(AccPostingException::class);
        $this->postEntry($owner->id, [
            'lines' => [
                ['account_code' => '9999', 'debit' => 100, 'credit' => 0],
                ['account_code' => AccAccount::AR_POS, 'debit' => 0, 'credit' => 100],
            ],
        ]);
    }

    public function test_unknown_doc_type_is_rejected(): void
    {
        $owner = User::factory()->create();

        $this->expectException(AccPostingException::class);
        $this->service->post('not_a_doc', [
            'network_owner_id' => $owner->id,
            'lines' => [
                ['account_code' => AccAccount::CASH_MAIN, 'debit' => 100, 'credit' => 0],
                ['account_code' => AccAccount::AR_POS, 'debit' => 0, 'credit' => 100],
            ],
        ]);
    }

    public function test_reversal_flips_every_line_and_is_idempotent(): void
    {
        $owner = User::factory()->create();
        $entry = $this->postEntry($owner->id);

        $reversal = $this->service->reverse($entry);

        $this->assertSame($entry->id, $reversal->reversal_of_id);
        $this->assertSame(0.0, $this->service->balanceOf($owner->id, 'box', 1));
        $this->assertSame(0.0, $this->service->balanceOf($owner->id, 'pos', 7));

        // Reversing twice returns the same reversal — no compounding.
        $again = $this->service->reverse($entry);
        $this->assertSame($reversal->id, $again->id);
        $this->assertSame(2, AccJournalEntry::count());
    }
}
