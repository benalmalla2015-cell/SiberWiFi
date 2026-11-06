<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * ACC-08 — posting-map row (PLAN §2.5): binds one platform source to
 * the account codes its poster uses. `mapping` is a sparse JSON
 * overlay on DEFAULTS — unknown keys are ignored, missing keys fall
 * back to the chart defaults below.
 */
class AccPostingMap extends Model
{
    protected $table = 'acc_posting_map';

    protected $fillable = [
        'network_owner_id', 'source', 'mapping', 'is_active',
    ];

    protected $casts = [
        'mapping' => 'array',
        'is_active' => 'boolean',
    ];

    public const SOURCE_CARD_PURCHASE = 'card_purchase_platform';

    public const SOURCES = [self::SOURCE_CARD_PURCHASE];

    /** Map keys accepted inside the JSON `mapping` column. */
    public const MAP_KEYS = [
        'cash_account',       // net proceeds landing account
        'revenue_account',    // gross sale revenue
        'commission_account', // platform commission expense
        'cogs_account',       // inventory cost of sold cards
        'inventory_account',  // card inventory asset
    ];

    public const DEFAULTS = [
        self::SOURCE_CARD_PURCHASE => [
            'cash_account' => AccAccount::CASH_MAIN,
            'revenue_account' => AccAccount::REVENUE_SALES,
            'commission_account' => AccAccount::EXPENSES,
            'cogs_account' => AccAccount::EXPENSES,
            'inventory_account' => AccAccount::INVENTORY_CARDS,
        ],
    ];

    /**
     * Effective account map for a source: stored JSON overlay merged
     * onto the defaults, restricted to known keys.
     *
     * @return array<string,string>
     */
    public static function accountsFor(int $ownerId, string $source): array
    {
        $base = self::DEFAULTS[$source] ?? [];
        $row = static::where('network_owner_id', $ownerId)
            ->where('source', $source)
            ->where('is_active', true)
            ->first();

        $overlay = is_array($row?->mapping) ? $row->mapping : [];

        return array_merge(
            $base,
            array_intersect_key($overlay, array_flip(self::MAP_KEYS))
        );
    }
}
