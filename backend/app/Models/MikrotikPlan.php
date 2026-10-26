<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MikrotikPlan extends Model
{
    protected $fillable = [
        'name', 'description', 'price', 'currency',
        'duration_days', 'features', 'is_active', 'sort_order',
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'features' => 'array',
        'is_active' => 'boolean',
    ];

    public function subscriptions()
    {
        return $this->hasMany(MikrotikSubscription::class, 'plan_id');
    }

    public function paymentRequests()
    {
        return $this->hasMany(MikrotikPaymentRequest::class, 'plan_id');
    }
}
