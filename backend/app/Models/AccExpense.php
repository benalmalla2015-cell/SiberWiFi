<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A posted expense (PLAN §2.3). Rows are never hard-deleted —
 * `void` flips the flag after the reversal entry restores the box.
 */
class AccExpense extends Model
{
    protected $table = 'acc_expenses';

    public const STATUS_POSTED = 'posted';
    public const STATUS_VOID = 'void';

    protected $fillable = [
        'network_owner_id', 'category_id', 'category_name', 'amount',
        'currency', 'exchange_rate', 'base_amount', 'cash_box_id',
        'agent_id', 'journal_entry_id', 'incurred_at', 'status',
        'note', 'idempotency_key',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'base_amount' => 'decimal:2',
        'exchange_rate' => 'decimal:6',
        'incurred_at' => 'datetime',
    ];

    public function category()
    {
        return $this->belongsTo(AccExpenseCategory::class, 'category_id');
    }

    public function box()
    {
        return $this->belongsTo(AccCashBox::class, 'cash_box_id');
    }

    public function entry()
    {
        return $this->belongsTo(AccJournalEntry::class, 'journal_entry_id');
    }
}
