<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Immutable journal entry — never updated or deleted after posting.
 * Corrections happen through a reversal entry (reversal_of_id).
 */
class AccJournalEntry extends Model
{
    protected $table = 'acc_journal_entries';

    protected $fillable = [
        'network_owner_id', 'entry_no', 'doc_type', 'doc_ref_id',
        'agent_id', 'date', 'currency', 'exchange_rate', 'memo',
        'idempotency_key', 'reversal_of_id', 'is_posted', 'posted_at',
    ];

    protected $casts = [
        'date' => 'date',
        'exchange_rate' => 'decimal:6',
        'is_posted' => 'boolean',
        'posted_at' => 'datetime',
    ];

    /** Document types accepted by AccPostingService (PLAN §2.3). */
    public const DOC_TYPES = [
        'sale', 'pos_sale', 'collection', 'expense', 'purchase',
        'return', 'damaged', 'withdrawal', 'adjustment', 'transfer',
        'card_purchase_platform',
    ];

    public function lines()
    {
        return $this->hasMany(AccJournalLine::class, 'entry_id');
    }

    public function reversalOf()
    {
        return $this->belongsTo(self::class, 'reversal_of_id');
    }

    public function reversals()
    {
        return $this->hasMany(self::class, 'reversal_of_id');
    }
}
