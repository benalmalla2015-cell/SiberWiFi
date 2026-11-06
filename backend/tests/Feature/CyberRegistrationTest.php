<?php

namespace Tests\Feature;

use App\Models\CyberSubscriber;
use App\Models\Directorate;
use App\Models\Region;
use App\Models\SubDirectorate;
use App\Models\User;
use App\Services\CyberSimService;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * CYB-03 feature tests — isolated schema on sqlite :memory:.
 *
 * The repo's full migration stack contains pre-CYB legacy migrations using
 * raw MySQL ENUM syntax that cannot run on sqlite (verified: every existing
 * Feature test fails the same way). This suite therefore builds only the
 * tables the endpoint touches: the read-only geo lookups plus this task's
 * own cyber_* migrations — executed from their real migration files.
 */
class CyberRegistrationTest extends TestCase
{
    private Directorate $directorate;

    private SubDirectorate $subDirectorate;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('local');
        $this->createSchema();
        $this->seedGeography();
    }

    private function createSchema(): void
    {
        Schema::create('regions', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('name_en')->nullable();
            $table->enum('type', ['north', 'south'])->default('north');
            $table->enum('currency', ['YER_OLD', 'YER_NEW'])->default('YER_OLD');
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
        Schema::create('directorates', function (Blueprint $table) {
            $table->id();
            $table->foreignId('region_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('name_en')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
        Schema::create('sub_directorates', function (Blueprint $table) {
            $table->id();
            $table->foreignId('directorate_id')->constrained('directorates')->cascadeOnDelete();
            $table->string('name');
            $table->string('name_en')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
        foreach (glob(database_path('migrations/*_create_cyber_*_table.php')) ?: [] as $file) {
            (require $file)->up();
        }
    }

    private function seedGeography(): void
    {
        $region = Region::create([
            'name' => 'عدن', 'type' => 'south', 'currency' => 'YER_NEW', 'is_active' => true,
        ]);
        $this->directorate = Directorate::create([
            'region_id' => $region->id, 'name' => 'عدن', 'is_active' => true,
        ]);
        $this->subDirectorate = SubDirectorate::create([
            'directorate_id' => $this->directorate->id, 'name' => 'المعلا', 'is_active' => true,
        ]);
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'full_name' => 'أحمد محمد صالح الحميري',
            'document_type' => 'national_id',
            'id_front_image' => UploadedFile::fake()->image('front.jpg'),
            'id_back_image' => UploadedFile::fake()->image('back.jpg'),
            'directorate_id' => $this->directorate->id,
            'sub_directorate_id' => $this->subDirectorate->id,
        ], $overrides);
    }

    public function test_registration_issues_unique_sim_number(): void
    {
        $response = $this->postJson('/api/cyber/register', $this->payload());

        $response->assertCreated()->assertJsonPath('success', true);
        $simNo = $response->json('data.sim_no');
        $this->assertMatchesRegularExpression('/^74\d{7}$/', $simNo);

        $this->assertDatabaseHas('cyber_subscribers', [
            'sim_no' => $simNo, 'full_name' => 'أحمد محمد صالح الحميري', 'status' => 'pending',
        ]);
        $this->assertDatabaseHas('cyber_documents', ['document_type' => 'national_id', 'review_status' => 'pending']);
        $this->assertDatabaseHas('cyber_identities', ['status' => 'pending', 'certificate_serial' => null]);

        $document = CyberSubscriber::where('sim_no', $simNo)->first()->documents->first();
        Storage::disk('local')->assertExists($document->front_path);
        Storage::disk('local')->assertExists($document->back_path);
    }

    public function test_passport_registration_needs_single_image(): void
    {
        $response = $this->postJson('/api/cyber/register', $this->payload([
            'document_type' => 'passport',
            'id_back_image' => null,
        ]));

        $response->assertCreated();
        $this->assertNull(
            CyberSubscriber::where('sim_no', $response->json('data.sim_no'))->first()
                ->documents->first()->back_path
        );
    }

    public function test_full_name_under_four_parts_is_rejected(): void
    {
        $this->postJson('/api/cyber/register', $this->payload(['full_name' => 'أحمد علي']))
            ->assertStatus(422)
            ->assertJsonValidationErrors('full_name');

        $this->assertDatabaseCount('cyber_subscribers', 0);
    }

    public function test_national_id_requires_back_image(): void
    {
        $this->postJson('/api/cyber/register', $this->payload(['id_back_image' => null]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('id_back_image');
    }

    public function test_sub_directorate_must_belong_to_directorate(): void
    {
        $otherRegion = Region::create(['name' => 'شمال', 'type' => 'north', 'currency' => 'YER_OLD', 'is_active' => true]);
        $otherDirectorate = Directorate::create(['region_id' => $otherRegion->id, 'name' => 'صنعاء', 'is_active' => true]);

        $this->postJson('/api/cyber/register', $this->payload(['directorate_id' => $otherDirectorate->id]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('sub_directorate_id');
    }

    public function test_concurrent_registration_retries_without_duplicating_sim(): void
    {
        // Deterministic collision: candidate() hands back an already-taken
        // number once, forcing the same atomic-retry path a real race hits.
        $this->partialMock(CyberSimService::class)
            ->shouldReceive('candidate')
            ->andReturn('740000001', '740000001', '740000002');

        $first = $this->postJson('/api/cyber/register', $this->payload());
        $second = $this->postJson('/api/cyber/register', $this->payload(['full_name' => 'سالم ناصر عبده قاسم']));

        $first->assertCreated();
        $second->assertCreated();
        $this->assertSame('740000001', $first->json('data.sim_no'));
        $this->assertSame('740000002', $second->json('data.sim_no'));
        $this->assertDatabaseCount('cyber_subscribers', 2);
    }

    public function test_sim_no_unique_constraint_is_atomic(): void
    {
        CyberSubscriber::create([
            'sim_no' => '740000009', 'full_name' => 'اختبار اختبار اختبار اختبار',
            'directorate_id' => $this->directorate->id,
            'sub_directorate_id' => $this->subDirectorate->id,
        ]);

        $this->expectException(UniqueConstraintViolationException::class);
        CyberSubscriber::create([
            'sim_no' => '740000009', 'full_name' => 'نسخة نسخة نسخة نسخة',
            'directorate_id' => $this->directorate->id,
            'sub_directorate_id' => $this->subDirectorate->id,
        ]);
    }

    public function test_subscriber_lookup_requires_auth_and_returns_data(): void
    {
        $simNo = $this->postJson('/api/cyber/register', $this->payload())->json('data.sim_no');

        $this->getJson("/api/cyber/subscribers/{$simNo}")->assertUnauthorized();

        Sanctum::actingAs(new User());
        $this->getJson("/api/cyber/subscribers/{$simNo}")
            ->assertOk()
            ->assertJsonPath('data.sim_no', $simNo)
            ->assertJsonPath('data.document_review', 'pending')
            ->assertJsonMissingPath('data.front_path');

        $this->getJson('/api/cyber/subscribers/749999999')->assertNotFound();
    }
}
