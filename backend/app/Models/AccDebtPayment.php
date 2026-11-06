<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One settlement against an acc_debts row — always created inside
 * the same transaction as its linked collection + journal entry.
 */
class AccDebtPayment extends Model
{
    protected $table = 'acc_debt_payments';

    protected $fillable = [
        'network_owner_id', 'debt_id', 'collection_id', 'amount',
        'base_amount', 'cash_box_id', 'journal_entry_id', 'agent_id',
        'paid_at', 'note',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'base_amount' => 'decimal:2',
        'paid_at' => 'datetime',
    ];

    public function debt()
    {
        return $this->belongsTo(AccDebt::class, 'debt_id');
    }

    public function collection()
    {
        return $this->belongsTo(AccCollection::class, 'collection_id');
    }
}
