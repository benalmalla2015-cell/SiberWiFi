<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Append-only points ledger (PLAN §2.2) — signed deltas feeding
 * acc_pos_points.points_balance. Rows are never updated/deleted.
 */
class AccPointsLedger extends Model
{
    protected $table = 'acc_points_ledger';

    public const UPDATED_AT = null;

    protected $fillable = [
        'network_owner_id', 'pos_id', 'reason', 'delta',
        'ref_type', 'ref_id', 'agent_id', 'balance_after', 'note',
        'created_at',
    ];

    protected $casts = [
        'delta' => 'decimal:2',
        'balance_after' => 'decimal:2',
        'created_at' => 'datetime',
    ];

    public const REASONS = [
        'order_purchase', 'conversion', 'adjustment', 'bonus',
    ];

    public function pos()
    {
        return $this->belongsTo(AccPosPoint::class, 'pos_id');
    }

    public function agent()
    {
        return $this->belongsTo(AccAgent::class, 'agent_id');
    }
}
