<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A tenant's accounting subscription (ACC-11, PLAN §6.1) — one row
 * per period, keyed by network_owner_id so owner + agents share it.
 * plan_id null = the free trial.
 */
class AccSubscription extends Model
{
    protected $table = 'acc_subscriptions';

    protected $fillable = [
        'network_owner_id', 'plan_id', 'status', 'starts_at', 'ends_at',
        'payment_request_id', 'granted_features', 'revoked_features',
    ];

    protected $casts = [
        'starts_at' => 'datetime',
        'ends_at' => 'datetime',
        'granted_features' => 'array',
        'revoked_features' => 'array',
    ];

    public function owner()
    {
        return $this->belongsTo(User::class, 'network_owner_id');
    }

    public function plan()
    {
        return $this->belongsTo(AccPlan::class, 'plan_id');
    }

    public function paymentRequest()
    {
        return $this->belongsTo(AccPaymentRequest::class);
    }

    public function getIsRunningAttribute(): bool
    {
        return $this->ends_at === null || $this->ends_at->isFuture();
    }
}
