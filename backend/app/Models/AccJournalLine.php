<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One debit/credit leg of a journal entry. The (party_type, party_id)
 * pair feeds acc_balances inside the same transaction.
 */
class AccJournalLine extends Model
{
    protected $table = 'acc_journal_lines';

    protected $fillable = [
        'entry_id', 'account_code', 'party_type', 'party_id',
        'debit', 'credit',
    ];

    protected $casts = [
        'debit' => 'decimal:2',
        'credit' => 'decimal:2',
    ];

    public const PARTY_TYPES = [
        'owner', 'pos', 'distributor', 'customer', 'supplier', 'box',
    ];

    public function entry()
    {
        return $this->belongsTo(AccJournalEntry::class, 'entry_id');
    }
}
