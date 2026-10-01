<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CommissionSetting extends Model
{
    protected $fillable = ['name', 'type', 'region_type', 'percentage', 'fixed_amount', 'is_global', 'is_active'];
    protected $casts    = [
        'percentage'   => 'decimal:2',
        'fixed_amount' => 'decimal:2',
        'is_active'    => 'boolean',
    ];

    public static function getRate(string $type): float
    {
        return (float) static::where('type', $type)->where('is_active', true)->value('percentage') ?? 0.0;
    }
}
