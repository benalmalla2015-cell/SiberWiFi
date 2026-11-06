<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A live CyberNet signal point on the client coverage map (CYB-08).
 * `host_name` is the serving host's NAS identifier; `name` is the
 * neighbourhood label rendered to subscribers.
 */
class CyberCoveragePoint extends Model
{
    protected $table = 'cyber_coverage_points';

    public const STATUS_ACTIVE = 'active';
    public const STATUS_PLANNED = 'planned';
    public const STATUS_OFFLINE = 'offline';

    protected $fillable = [
        'name', 'city', 'host_name', 'latitude', 'longitude',
        'status', 'sort_order',
    ];

    protected $casts = [
        'latitude' => 'decimal:7',
        'longitude' => 'decimal:7',
    ];

    public function scopeActive($query)
    {
        return $query->where('status', self::STATUS_ACTIVE)->orderBy('sort_order');
    }
}
