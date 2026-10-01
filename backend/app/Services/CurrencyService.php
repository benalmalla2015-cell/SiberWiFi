<?php

namespace App\Services;

use App\Models\ExchangeRateSetting;

/**
 * Converts amounts between the two regional currencies used across the
 * app: the "north" currency (ريال يمني قديم) and the "south" currency
 * (ريال يمني). The exchange rate is configured by the admin from
 * "إعدادات سعر الصرف" as a single global setting:
 *   - base_currency: which currency the rate is anchored to.
 *   - rate_percent: how many units of the OTHER currency equal 100 units
 *     of the base currency (e.g. base=north, rate_percent=380 means
 *     100 ريال شمال = 380 ريال جنوب).
 */
class CurrencyService
{
    public static function multiplierNorthToSouth(): float
    {
        $setting = ExchangeRateSetting::current();
        if (!$setting) {
            return 1.0;
        }

        $ratio = ((float) $setting->rate_percent) / 100;

        return $setting->base_currency === 'north' ? $ratio : (1 / $ratio);
    }

    /**
     * Convert an amount from one regional currency to another.
     * $from / $to are 'north' or 'south'.
     */
    public static function convert(float $amount, ?string $from, ?string $to): float
    {
        $from = $from ?: 'north';
        $to = $to ?: 'north';

        if ($from === $to) {
            return $amount;
        }

        $northToSouth = self::multiplierNorthToSouth();

        if ($from === 'north' && $to === 'south') {
            return round($amount * $northToSouth, 2);
        }

        if ($from === 'south' && $to === 'north') {
            return round($amount / $northToSouth, 2);
        }

        return $amount;
    }

    public static function isConversionNeeded(?string $from, ?string $to): bool
    {
        return $from && $to && $from !== $to;
    }

    public static function currencyLabel(?string $type): string
    {
        return $type === 'south' ? 'ريال يمني (جنوب)' : 'ريال يمني قديم (شمال)';
    }
}
