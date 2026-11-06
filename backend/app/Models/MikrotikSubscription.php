<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MikrotikSubscription extends Model
{
    protected $fillable = [
        'user_id', 'plan_id', 'status', 'starts_at', 'ends_at',
        'payment_request_id', 'granted_features', 'revoked_features',
    ];

    protected $casts = [
        'starts_at' => 'datetime',
        'ends_at' => 'datetime',
        'granted_features' => 'array',
        'revoked_features' => 'array',
    ];

    public function user() { return $this->belongsTo(User::class); }
    public function plan() { return $this->belongsTo(MikrotikPlan::class, 'plan_id'); }

    public function paymentRequest()
    {
        return $this->belongsTo(MikrotikPaymentRequest::class);
    }

    public function getIsRunningAttribute(): bool
    {
        return $this->ends_at === null || $this->ends_at->isFuture();
    }
}
