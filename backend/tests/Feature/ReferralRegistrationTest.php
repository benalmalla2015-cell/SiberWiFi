<?php

namespace Tests\Feature;

use App\Models\Directorate;
use App\Models\Region;
use App\Models\SubDirectorate;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ReferralRegistrationTest extends TestCase
{
    use RefreshDatabase;

    public function test_registration_records_referral_when_no_commission_is_configured(): void
    {
        $region = Region::create([
            'name' => 'منطقة اختبار',
            'type' => 'north',
            'currency' => 'YER_OLD',
            'is_active' => true,
        ]);
        $directorate = Directorate::create([
            'region_id' => $region->id,
            'name' => 'محافظة اختبار',
            'is_active' => true,
        ]);
        $subDirectorate = SubDirectorate::create([
            'directorate_id' => $directorate->id,
            'name' => 'مديرية اختبار',
            'is_active' => true,
        ]);
        $referrer = User::factory()->create([
            'phone' => '711111111',
            'referral_code' => '5R2S24BP',
            'region_type' => 'north',
        ]);

        $response = $this->postJson('/api/auth/register', [
            'name' => 'مستخدم اختبار جديد كامل',
            'phone' => '766766766',
            'password' => 'password',
            'password_confirmation' => 'password',
            'region_id' => $region->id,
            'directorate_id' => $directorate->id,
            'sub_directorate_id' => $subDirectorate->id,
            'referral_code' => '5R2S24BP',
        ]);

        $response->assertCreated();
        $referred = User::where('phone', '766766766')->firstOrFail();

        $this->assertSame($referrer->id, $referred->referred_by);
        $this->assertDatabaseHas('referrals', [
            'referrer_id' => $referrer->id,
            'referred_id' => $referred->id,
            'transaction_id' => null,
            'commission_amount' => 0,
            'is_paid' => false,
        ]);
    }
}
