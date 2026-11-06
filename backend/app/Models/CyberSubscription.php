<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A subscriber's activated package window (CYB-04). `radius_reply`
 * caches the authorize-time attributes; `consumed_bytes` is updated
 * by the accounting event stream.
 */
class CyberSubscription extends Model
{
    protected $table = 'cyber_subscriptions';

    public const STATUS_ACTIVE = 'active';
    public const STATUS_EXHAUSTED = 'exhausted';
    public const STATUS_EXPIRED = 'expired';
    public const STATUS_CANCELLED = 'cancelled';

    protected $fillable = [
        'subscriber_id', 'package_id', 'starts_at', 'ends_at',
        'data_limit_bytes', 'consumed_bytes', 'status', 'radius_reply',
        'ended_at', 'idempotency_key',
    ];

    protected $casts = [
        'starts_at' => 'datetime',
        'ends_at' => 'datetime',
        'ended_at' => 'datetime',
        'radius_reply' => 'array',
        'data_limit_bytes' => 'integer',
        'consumed_bytes' => 'integer',
    ];

    public function package()
    {
        return $this->belongsTo(CyberPackage::class, 'package_id');
    }

    public function sessions()
    {
        return $this->hasMany(CyberSession::class, 'subscription_id');
    }

    public function getIsActiveAttribute(): bool
    {
        return $this->status === self::STATUS_ACTIVE;
    }

    public function getIsDueAttribute(): bool
    {
        if ($this->status !== self::STATUS_ACTIVE) {
            return false;
        }
        if ($this->ends_at !== null && $this->ends_at->isPast()) {
            return true;
        }

        return $this->data_limit_bytes !== null
            && $this->consumed_bytes >= $this->data_limit_bytes;
    }
}
