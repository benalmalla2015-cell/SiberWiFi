<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Running balance per business party. Updated atomically inside the
 * posting transaction — balance += (debit − credit) for every posted
 * line that carries party info.
 */
class AccBalance extends Model
{
    protected $table = 'acc_balances';

    protected $fillable = [
        'network_owner_id', 'party_type', 'party_id', 'balance',
    ];

    protected $casts = [
        'balance' => 'decimal:2',
    ];
}
