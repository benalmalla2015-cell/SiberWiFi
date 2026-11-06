<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One commission ledger row per agent top-up (CYB-07).
 * Credited automatically by CreditCyberAgentCommission when
 * CyberTopupCompleted fires; unique topup_id keeps it idempotent.
 */
class CyberAgentCommission extends Model
{
    protected $table = 'cyber_agent_commissions';

    public const STATUS_ACCRUED = 'accrued';
    public const STATUS_PAID_OUT = 'paid_out';
    public const STATUS_VOID = 'void';

    protected $fillable = [
        'agent_id', 'topup_id', 'subscriber_id', 'sim_no',
        'topup_amount', 'percent', 'amount', 'currency', 'status',
    ];

    protected $casts = [
        'topup_amount' => 'decimal:2',
        'percent' => 'decimal:2',
        'amount' => 'decimal:2',
    ];

    public function agent()
    {
        return $this->belongsTo(User::class, 'agent_id');
    }

    public function topup()
    {
        return $this->belongsTo(CyberTopup::class, 'topup_id');
    }
}
