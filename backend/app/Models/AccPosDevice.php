<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A physical terminal bound to a POS point (PLAN §2.2).
 * device_uid is unique per owner so one handset can't serve two
 * outlets at once.
 */
class AccPosDevice extends Model
{
    protected $table = 'acc_pos_devices';

    protected $fillable = [
        'network_owner_id', 'pos_point_id', 'device_uid',
        'device_name', 'model', 'agent_user_id', 'bound_at',
    ];

    protected $casts = [
        'bound_at' => 'datetime',
    ];

    public function posPoint()
    {
        return $this->belongsTo(AccPosPoint::class, 'pos_point_id');
    }

    public function agentUser()
    {
        return $this->belongsTo(User::class, 'agent_user_id');
    }
}
