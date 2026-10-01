<?php

namespace Tests\Unit;

use App\Models\DailyOffer;
use PHPUnit\Framework\TestCase;

class ExampleTest extends TestCase
{
    /**
     * A basic test example.
     */
    public function test_that_true_is_true(): void
    {
        $this->assertTrue(true);
    }

    public function test_unscoped_offer_applies_to_every_category(): void
    {
        $offer = new DailyOffer([
            'apply_to_all_categories' => false,
            'category_ids' => null,
            'discount_percent' => 10,
        ]);

        $this->assertTrue($offer->appliesToCategory(42));
        $this->assertSame(900.0, $offer->applyToUnitPrice(1000));
    }

    public function test_legacy_discount_is_used_for_multiple_card_total(): void
    {
        $offer = new DailyOffer([
            'discount_percent' => 0,
            'discount_percentage' => 25,
        ]);

        $this->assertSame(25.0, $offer->effectiveDiscountPercent());
        $this->assertSame(1500.0, $offer->applyToUnitPrice(1000) * 2);
    }

    public function test_best_applicable_offer_supports_selected_categories(): void
    {
        $lower = new DailyOffer(['category_ids' => ['5'], 'discount_percent' => 10]);
        $higher = new DailyOffer(['category_ids' => [5], 'discount_percent' => 20]);

        $this->assertSame($higher, DailyOffer::pickForCategory([$lower, $higher], 5));
        $this->assertNull(DailyOffer::pickForCategory([$lower, $higher], 6));
    }
}
