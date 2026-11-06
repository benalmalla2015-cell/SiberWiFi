<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Append-only profit ledger (PLAN §2.2) — commission accruals and
 * profit withdrawals for a 'pos' (acc_pos_points) or a
 * 'distributor' (acc_agents) party. Rows are never
 * updated/deleted.
 */
class AccProfitLedger extends Model
{
    protected $table = 'acc_profit_ledger';

    public const UPDATED_AT = null;

    protected $fillable = [
        'network_owner_id', 'party_type', 'party_id', 'reason', 'delta',
        'ref_type', 'ref_id', 'agent_id', 'note', 'created_at',
    ];

    protected $casts = [
        'delta' => 'decimal:2',
        'created_at' => 'datetime',
    ];

    public const PARTY_TYPES = ['pos', 'distributor'];
    public const REASONS = ['sale_commission', 'withdrawal', 'adjustment'];

    public function agent()
    {
        return $this->belongsTo(AccAgent::class, 'agent_id');
    }
}
