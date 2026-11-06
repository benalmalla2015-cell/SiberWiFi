<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A cash movement between two boxes — one atomic transfer entry
 * with both legs posted in base currency.
 */
class AccCashTransfer extends Model
{
    protected $table = 'acc_cash_transfers';

    protected $fillable = [
        'network_owner_id', 'from_box_id', 'to_box_id',
        'amount', 'to_amount', 'currency', 'exchange_rate',
        'agent_id', 'journal_entry_id', 'note', 'idempotency_key',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'to_amount' => 'decimal:2',
        'exchange_rate' => 'decimal:6',
    ];

    public function fromBox()
    {
        return $this->belongsTo(AccCashBox::class, 'from_box_id');
    }

    public function toBox()
    {
        return $this->belongsTo(AccCashBox::class, 'to_box_id');
    }

    public function entry()
    {
        return $this->belongsTo(AccJournalEntry::class, 'journal_entry_id');
    }
}
