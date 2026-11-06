<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Discount/reward tier (PLAN §2.4, ACC-10).
 *
 * A bracket over the document's `basis` total (qty | amount):
 * [min, max] — NULL max = open-ended. The winning tier of each
 * `mode` applies inside the document's atomic posting cycle:
 *
 *   direct_percent → discount off the document value
 *   points         → bonus points to the POS point
 *   profit_balance → bonus profit balance to the POS point
 *   commission     → extra commission to the distributor
 */
class AccDiscountTier extends Model
{
    protected $table = 'acc_discount_tiers';

    protected $fillable = [
        'network_owner_id', 'mode', 'basis', 'min', 'max',
        'reward_value', 'reward_unit', 'sort_order', 'is_active',
    ];

    protected $casts = [
        'min' => 'decimal:2',
        'max' => 'decimal:2',
        'reward_value' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public const MODE_COMMISSION = 'commission';
    public const MODE_POINTS = 'points';
    public const MODE_PROFIT = 'profit_balance';
    public const MODE_PERCENT = 'direct_percent';

    public const MODES = [
        self::MODE_COMMISSION,
        self::MODE_POINTS,
        self::MODE_PROFIT,
        self::MODE_PERCENT,
    ];

    public const BASIS_QTY = 'qty';
    public const BASIS_AMOUNT = 'amount';

    public const BASES = [self::BASIS_QTY, self::BASIS_AMOUNT];

    public const UNIT_PERCENT = 'percent';
    public const UNIT_FIXED = 'fixed';

    public const UNITS = [self::UNIT_PERCENT, self::UNIT_FIXED];

    /** Does this bracket contain the given basis total? */
    public function matches(float $basisValue): bool
    {
        if ($basisValue < (float) $this->min) {
            return false;
        }

        return $this->max === null || $basisValue <= (float) $this->max;
    }

    /**
     * The reward expressed in value units: percent → share of the
     * document amount; fixed → the flat configured value.
     */
    public function rewardFor(float $docAmount): float
    {
        $reward = $this->reward_unit === self::UNIT_FIXED
            ? (float) $this->reward_value
            : $docAmount * (float) $this->reward_value / 100;

        return round(max(0.0, $reward), 2);
    }

    /** Arabic label for the mode (API/UI display). */
    public static function modeLabel(string $mode): string
    {
        return [
            self::MODE_COMMISSION => 'عمولة إضافية للموزع',
            self::MODE_POINTS => 'نقاط مكافأة',
            self::MODE_PROFIT => 'رصيد أرباح',
            self::MODE_PERCENT => 'خصم مباشر',
        ][$mode] ?? $mode;
    }
}
