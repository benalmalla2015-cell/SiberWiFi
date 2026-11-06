<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Per-subscriber «سلفني» credit state (CYB-06): the allowed borrow
 * ceiling plus the currently unpaid debt. Mutate only inside
 * CyberCreditService under lockForUpdate.
 */
class CyberCreditLimit extends Model
{
    protected $table = 'cyber_credit_limits';

    protected $fillable = [
        'subscriber_id', 'limit_amount', 'outstanding',
    ];

    protected $casts = [
        'limit_amount' => 'decimal:2',
        'outstanding' => 'decimal:2',
    ];

    public function subscriber()
    {
        return $this->belongsTo(CyberSubscriber::class, 'subscriber_id');
    }
}
