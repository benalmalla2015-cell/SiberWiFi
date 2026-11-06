<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * An agent→subscriber balance credit (CYB-04), idempotent on
 * `idempotency_key`.
 */
class CyberTopup extends Model
{
    protected $table = 'cyber_topups';

    protected $fillable = [
        'agent_id', 'subscriber_id', 'sim_no', 'amount', 'currency',
        'status', 'idempotency_key', 'meta',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'meta' => 'array',
    ];

    public function agent()
    {
        return $this->belongsTo(User::class, 'agent_id');
    }
}
