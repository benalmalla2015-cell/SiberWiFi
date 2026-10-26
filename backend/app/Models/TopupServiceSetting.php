<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TopupServiceSetting extends Model
{
    protected $fillable = [
        'code', 'name_ar', 'category', 'provider_endpoint', 'account',
        'fee_type', 'fee_value', 'sort_order', 'is_active', 'meta',
    ];

    protected $casts = [
        'fee_value' => 'decimal:2',
        'is_active' => 'boolean',
        'meta' => 'array',
    ];
}
