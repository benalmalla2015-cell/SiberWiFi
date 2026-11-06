<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A subscriber→subscriber balance transfer (CYB-06), idempotent on
 * `idempotency_key`. Always written inside CyberTransferService's
 * locked transaction — never mutate balances against it directly.
 */
class CyberTransfer extends Model
{
    protected $table = 'cyber_transfers';

    public const STATUS_COMPLETED = 'completed';
    public const STATUS_FAILED = 'failed';
    public const STATUS_REVERSED = 'reversed';

    protected $fillable = [
        'from_subscriber_id', 'to_subscriber_id', 'from_sim_no', 'to_sim_no',
        'amount', 'currency', 'status', 'idempotency_key', 'meta',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'meta' => 'array',
    ];

    public function from()
    {
        return $this->belongsTo(CyberSubscriber::class, 'from_subscriber_id');
    }

    public function to()
    {
        return $this->belongsTo(CyberSubscriber::class, 'to_subscriber_id');
    }
}
