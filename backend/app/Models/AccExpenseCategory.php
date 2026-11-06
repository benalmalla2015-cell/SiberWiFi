<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Per-tenant expense vocabulary (PLAN §2.3). Seeded lazily with
 * the everyday network costs on first read/write.
 */
class AccExpenseCategory extends Model
{
    protected $table = 'acc_expense_categories';

    protected $fillable = [
        'network_owner_id', 'name', 'sort_order', 'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    /** The default vocabulary for a fresh tenant. */
    public static function defaultNames(): array
    {
        return ['رواتب', 'إيجار', 'وقود ومولدة', 'صيانة', 'إنترنت واشتراكات', 'أخرى'];
    }

    /** Idempotent via the (owner, name) unique index. */
    public static function ensureDefaultsFor(int $ownerId): void
    {
        $now = now();
        $rows = array_map(fn (string $name, int $i) => [
            'network_owner_id' => $ownerId,
            'name' => $name,
            'sort_order' => $i,
            'is_active' => true,
            'created_at' => $now,
            'updated_at' => $now,
        ], self::defaultNames(), array_keys(self::defaultNames()));

        static::insertOrIgnore($rows);
    }
}
