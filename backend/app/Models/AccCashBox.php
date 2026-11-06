<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A cash drawer (PLAN §2.3). The default box is created lazily on
 * first money movement; its balance is tracked per-box in the
 * box's own currency while the journal posts base amounts against
 * party (`box`, box_id).
 */
class AccCashBox extends Model
{
    protected $table = 'acc_cash_boxes';

    protected $fillable = [
        'network_owner_id', 'name', 'currency', 'balance',
        'is_default', 'is_active',
    ];

    protected $casts = [
        'balance' => 'decimal:2',
        'is_default' => 'boolean',
        'is_active' => 'boolean',
    ];

    /** The tenant's default box — created on first use. */
    public static function ensureDefaultFor(int $ownerId, string $currency = 'north'): self
    {
        $box = static::where('network_owner_id', $ownerId)
            ->where('is_default', true)
            ->where('is_active', true)
            ->first();

        if ($box !== null) {
            return $box;
        }

        return static::create([
            'network_owner_id' => $ownerId,
            'name' => 'الصندوق الرئيسي',
            'currency' => $currency,
            'balance' => 0,
            'is_default' => true,
            'is_active' => true,
        ]);
    }

    public function transfersOut()
    {
        return $this->hasMany(AccCashTransfer::class, 'from_box_id');
    }

    public function transfersIn()
    {
        return $this->hasMany(AccCashTransfer::class, 'to_box_id');
    }
}
