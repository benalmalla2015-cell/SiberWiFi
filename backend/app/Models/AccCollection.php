<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A cash collection (PLAN §2.3). `base_amount` is the
 * north-normalized figure the journal posts; `amount`+`currency`
 * keep the document's own denomination.
 */
class AccCollection extends Model
{
    protected $table = 'acc_collections';

    public const PARTY_TYPES = ['pos', 'distributor', 'customer', 'person'];

    protected $fillable = [
        'network_owner_id', 'collector_agent_id', 'party_type',
        'party_id', 'party_name', 'phone', 'amount', 'currency',
        'exchange_rate', 'base_amount', 'cash_box_id', 'debt_id',
        'journal_entry_id', 'collected_at', 'note', 'idempotency_key',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'base_amount' => 'decimal:2',
        'exchange_rate' => 'decimal:6',
        'collected_at' => 'datetime',
    ];

    public function box()
    {
        return $this->belongsTo(AccCashBox::class, 'cash_box_id');
    }

    public function collector()
    {
        return $this->belongsTo(AccAgent::class, 'collector_agent_id');
    }

    public function debt()
    {
        return $this->belongsTo(AccDebt::class, 'debt_id');
    }

    public function entry()
    {
        return $this->belongsTo(AccJournalEntry::class, 'journal_entry_id');
    }
}
