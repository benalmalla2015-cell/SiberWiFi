<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A receivable/payable the owner tracks to settlement (PLAN §2.3).
 * `supplier` debts are payables (we owe) — every other party_type
 * is a receivable (they owe us).
 */
class AccDebt extends Model
{
    protected $table = 'acc_debts';

    public const PARTY_TYPES = ['pos', 'distributor', 'customer', 'person', 'supplier'];

    public const STATUS_OPEN = 'open';
    public const STATUS_PARTIAL = 'partial';
    public const STATUS_PAID = 'paid';

    protected $fillable = [
        'network_owner_id', 'party_type', 'party_id', 'party_name',
        'phone', 'amount_due', 'amount_paid', 'base_due', 'base_paid',
        'currency', 'exchange_rate', 'status', 'due_date',
        'agent_id', 'journal_entry_id', 'note',
    ];

    protected $casts = [
        'amount_due' => 'decimal:2',
        'amount_paid' => 'decimal:2',
        'base_due' => 'decimal:2',
        'base_paid' => 'decimal:2',
        'exchange_rate' => 'decimal:6',
        'due_date' => 'date',
    ];

    /** True when the owner owes the party (payable side). */
    public function isPayable(): bool
    {
        return $this->party_type === 'supplier';
    }

    public function remaining(): float
    {
        return max(0.0, (float) $this->amount_due - (float) $this->amount_paid);
    }

    public function payments()
    {
        return $this->hasMany(AccDebtPayment::class, 'debt_id');
    }

    public function entry()
    {
        return $this->belongsTo(AccJournalEntry::class, 'journal_entry_id');
    }
}
