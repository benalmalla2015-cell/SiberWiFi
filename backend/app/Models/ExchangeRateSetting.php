<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ExchangeRateSetting extends Model
{
    protected $fillable = [
        'base_currency', 'rate_percent', 'is_active', 'description',
    ];

    protected $casts = [
        'rate_percent' => 'decimal:4',
        'is_active'    => 'boolean',
    ];

    public static function current(): ?self
    {
        return static::where('is_active', true)->latest('id')->first();
    }
}
