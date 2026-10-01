<?php

namespace Tests\Feature;

use App\Models\CardCategory;
use App\Models\Network;
use App\Models\User;
use App\Models\WalletLog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AdvanceEligibilityTest extends TestCase
{
    use RefreshDatabase;

    public function test_depleted_customer_with_legacy_manual_topup_is_eligible(): void
    {
        $user = User::factory()->create(['balance' => 0, 'available_balance' => 0]);

        WalletLog::create([
            'user_id' => $user->id,
            'type' => 'credit',
            'amount' => 1000,
            'balance_before' => 0,
            'balance_after' => 1000,
            'description' => 'شحن رصيد يدوي',
            'reference_type' => 'manual',
        ]);

        $this->assertTrue($user->isEligibleForAdvance());
    }

    public function test_depleted_customer_with_completed_wallet_purchase_is_eligible(): void
    {
        $user = User::factory()->create(['balance' => 0, 'available_balance' => 0]);

        WalletLog::create([
            'user_id' => $user->id,
            'type' => 'debit',
            'amount' => 100,
            'balance_before' => 100,
            'balance_after' => 0,
            'description' => 'شراء كرت شحن',
            'reference_type' => 'purchase',
        ]);

        $this->assertTrue($user->isEligibleForAdvance());
    }

    public function test_cashback_alone_does_not_enable_advance(): void
    {
        $user = User::factory()->create(['balance' => 0, 'available_balance' => 0]);

        WalletLog::create([
            'user_id' => $user->id,
            'type' => 'credit',
            'amount' => 10,
            'balance_before' => 0,
            'balance_after' => 10,
            'description' => 'كاشباك',
            'reference_type' => 'cashback',
        ]);

        $this->assertFalse($user->isEligibleForAdvance());
    }

    public function test_network_detects_available_advance_from_categories_even_when_cached_flag_is_stale(): void
    {
        $owner = User::factory()->create();
        $network = Network::create([
            'user_id' => $owner->id,
            'name' => 'شبكة اختبار',
            'slug' => 'advance-test-network',
            'status' => 'active',
            'supports_credit' => false,
        ]);

        CardCategory::create([
            'network_id' => $network->id,
            'name' => 'فئة سلفني',
            'price' => 100,
            'value' => 100,
            'is_active' => true,
            'advance_enabled' => true,
            'advance_status' => 'approved',
            'advance_max_cards' => 5,
            'advance_used_count' => 0,
        ]);

        $this->assertTrue($network->hasAvailableAdvance());
    }
}
