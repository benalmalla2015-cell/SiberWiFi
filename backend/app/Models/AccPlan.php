<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Accounting subscription plan (ACC-11, PLAN §6.1) — admin-managed
 * catalog mirroring MikrotikPlan.
 */
class AccPlan extends Model
{
    protected $table = 'acc_plans';

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
        return $this->hasMany(AccSubscription::class, 'plan_id');
    }

    public function paymentRequests()
    {
        return $this->hasMany(AccPaymentRequest::class, 'plan_id');
    }
}
