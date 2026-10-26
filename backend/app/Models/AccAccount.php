<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Simplified chart of accounts, one chart per network owner.
 * The default chart (PLAN §2.3) is seeded lazily on first posting —
 * `is_system` marks rows that must never be deleted/renamed.
 */
class AccAccount extends Model
{
    protected $table = 'acc_accounts';

    protected $fillable = [
        'network_owner_id', 'code', 'name', 'type',
        'parent_code', 'is_system', 'is_active',
    ];

    protected $casts = [
        'is_system' => 'boolean',
        'is_active' => 'boolean',
    ];

    public const TYPE_ASSET = 'asset';
    public const TYPE_LIABILITY = 'liability';
    public const TYPE_EQUITY = 'equity';
    public const TYPE_REVENUE = 'revenue';
    public const TYPE_EXPENSE = 'expense';

    // ── Default chart codes (PLAN §2.3) ──────────────────────────
    public const CASH_MAIN = '1000';
    public const INVENTORY_CARDS = '1100';
    public const AR_POS = '1200';
    public const AR_DISTRIBUTORS = '1210';
    public const POS_PROFITS = '2100';
    public const CUSTOMER_BALANCES = '2200';
    public const AP_SUPPLIERS = '2300';
    public const EQUITY = '3000';
    public const REVENUE_SALES = '4000';
    public const REVENUE_COMMISSIONS = '4100';
    public const EXPENSES = '5000';

    /**
     * The seeded chart: main cash box, card inventory, POS/distributor
     * receivables, sales revenue, commissions, expenses, POS profit
     * and customer balances — plus supplier payables and owner equity
     * needed by the purchases/adjustment flows (ACC-05+).
     */
    public static function defaultChart(): array
    {
        return [
            ['code' => self::CASH_MAIN, 'name' => 'صندوق رئيسي', 'type' => self::TYPE_ASSET],
            ['code' => self::INVENTORY_CARDS, 'name' => 'مخزون كروت', 'type' => self::TYPE_ASSET],
            ['code' => self::AR_POS, 'name' => 'ذمم نقاط بيع', 'type' => self::TYPE_ASSET],
            ['code' => self::AR_DISTRIBUTORS, 'name' => 'ذمم موزعين', 'type' => self::TYPE_ASSET],
            ['code' => self::POS_PROFITS, 'name' => 'أرباح نقاط', 'type' => self::TYPE_LIABILITY],
            ['code' => self::CUSTOMER_BALANCES, 'name' => 'أرصدة عملاء', 'type' => self::TYPE_LIABILITY],
            ['code' => self::AP_SUPPLIERS, 'name' => 'ذمم موردين', 'type' => self::TYPE_LIABILITY],
            ['code' => self::EQUITY, 'name' => 'حقوق الملكية', 'type' => self::TYPE_EQUITY],
            ['code' => self::REVENUE_SALES, 'name' => 'إيراد مبيعات', 'type' => self::TYPE_REVENUE],
            ['code' => self::REVENUE_COMMISSIONS, 'name' => 'عمولات', 'type' => self::TYPE_REVENUE],
            ['code' => self::EXPENSES, 'name' => 'مصروفات', 'type' => self::TYPE_EXPENSE],
        ];
    }

    /**
     * Lazily seed the owner's default chart — idempotent via the
     * (network_owner_id, code) unique index.
     */
    public static function ensureDefaultsFor(int $ownerId): void
    {
        $now = now();
        $rows = array_map(fn (array $a) => [
            'network_owner_id' => $ownerId,
            'code' => $a['code'],
            'name' => $a['name'],
            'type' => $a['type'],
            'is_system' => true,
            'is_active' => true,
            'created_at' => $now,
            'updated_at' => $now,
        ], self::defaultChart());

        static::insertOrIgnore($rows);
    }

    public function lines()
    {
        return $this->hasMany(AccJournalLine::class, 'account_code', 'code')
            ->whereHas('entry', fn ($q) => $q->where('network_owner_id', $this->network_owner_id));
    }
}
