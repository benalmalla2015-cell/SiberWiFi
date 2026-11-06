<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A sellable CyberNet package (CYB-04): duration + data quota + YER
 * price + optional Mikrotik-Rate-Limit override.
 */
class CyberPackage extends Model
{
    protected $table = 'cyber_packages';

    protected $fillable = [
        'name', 'name_ar', 'duration_days', 'data_limit_gb',
        'price', 'rate_limit', 'is_active', 'sort_order',
    ];

    protected $casts = [
        'data_limit_gb' => 'decimal:3',
        'price' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public function scopeActive($query)
    {
        return $query->where('is_active', true)->orderBy('sort_order');
    }

    public function getDataLimitBytesAttribute(): ?int
    {
        if ($this->data_limit_gb === null) {
            return null;
        }

        return (int) round(((float) $this->data_limit_gb) * 1024 * 1024 * 1024);
    }
}
