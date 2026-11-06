<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Operating sub-account inside an owner's tenant (PLAN §1).
 *
 * Binds an existing `users` row to a working role — the same owner
 * app reads it at login and routes the employee to the right
 * surface (admin = full section, distributor, pos). A suspended
 * status cuts API access without touching the user account.
 */
class AccAgent extends Model
{
    protected $table = 'acc_agents';

    protected $fillable = [
        'network_owner_id', 'user_id', 'role', 'display_name', 'phone',
        'daily_limit_per_category', 'cash_allowed', 'credit_allowed',
        'status', 'commission_mode', 'commission_value',
    ];

    protected $casts = [
        'daily_limit_per_category' => 'array',
        'cash_allowed' => 'boolean',
        'credit_allowed' => 'boolean',
        'commission_value' => 'decimal:2',
    ];

    public const ROLES = ['admin', 'distributor', 'pos'];
    public const ROLE_OWNER = 'owner';

    public const STATUS_ACTIVE = 'active';
    public const STATUS_SUSPENDED = 'suspended';

    public const COMMISSION_MODES = ['none', 'percent', 'fixed', 'points'];

    public function owner()
    {
        return $this->belongsTo(User::class, 'network_owner_id');
    }

    public function user()
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function posPoints()
    {
        return $this->hasMany(AccPosPoint::class, 'agent_id');
    }
}
