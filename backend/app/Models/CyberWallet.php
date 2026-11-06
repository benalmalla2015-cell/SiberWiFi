<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One CyberNet wallet per subscriber (CYB-04), balance in YER.
 * Always mutate the balance inside CyberBillingService (locked
 * increment/decrement) — never by direct assignment.
 */
class CyberWallet extends Model
{
    protected $table = 'cyber_wallets';

    protected $fillable = [
        'subscriber_id', 'balance', 'currency',
    ];

    protected $casts = [
        'balance' => 'decimal:2',
    ];
}
