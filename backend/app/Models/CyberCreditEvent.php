<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * «سلفني» ledger entry (CYB-06): a borrow grant or an automatic repay
 * collected from an incoming top-up/transfer (source in `meta`).
 */
class CyberCreditEvent extends Model
{
    protected $table = 'cyber_credit_events';

    public const TYPE_BORROW = 'borrow';
    public const TYPE_REPAY = 'repay';

    protected $fillable = [
        'subscriber_id', 'sim_no', 'type', 'amount', 'outstanding_after',
        'idempotency_key', 'meta',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'outstanding_after' => 'decimal:2',
        'meta' => 'array',
    ];

    public function subscriber()
    {
        return $this->belongsTo(CyberSubscriber::class, 'subscriber_id');
    }
}
