<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Point-of-sale outlet (PLAN §2.2). `agent_id` binds the acc_agents
 * row of role `pos` that operates this point; points/profit balances
 * are the POS-side ledgers fed by later posting sprints.
 */
class AccPosPoint extends Model
{
    protected $table = 'acc_pos_points';

    protected $fillable = [
        'network_owner_id', 'agent_id', 'name', 'location',
        'owner_name', 'phone', 'status',
        'credit_limit', 'points_balance', 'profit_balance',
    ];

    protected $casts = [
        'credit_limit' => 'decimal:2',
        'points_balance' => 'decimal:2',
        'profit_balance' => 'decimal:2',
    ];

    public const STATUS_ACTIVE = 'active';
    public const STATUS_SUSPENDED = 'suspended';

    public function owner()
    {
        return $this->belongsTo(User::class, 'network_owner_id');
    }

    public function agent()
    {
        return $this->belongsTo(AccAgent::class, 'agent_id');
    }

    public function devices()
    {
        return $this->hasMany(AccPosDevice::class, 'pos_point_id');
    }
}
