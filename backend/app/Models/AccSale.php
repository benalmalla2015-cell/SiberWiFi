<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A distributor/owner sale to a POS point (PLAN §2.2, ACC-06).
 * The document row behind the atomic sale cycle — rows are never
 * deleted; corrections go through reversal journal entries.
 *
 * payment_kind cash|credit|partial: `paid_amount` reached the cash
 * box at posting; the remainder sits on the POS's receivable and is
 * tracked to settlement through `debt_id` → acc_debts.
 */
class AccSale extends Model
{
    protected $table = 'acc_sales';

    public const KIND_CASH = 'cash';
    public const KIND_CREDIT = 'credit';
    public const KIND_PARTIAL = 'partial';
    public const KINDS = [self::KIND_CASH, self::KIND_CREDIT, self::KIND_PARTIAL];

    public const STATUS_POSTED = 'posted';
    public const STATUS_VOID = 'void';

    protected $fillable = [
        'network_owner_id', 'sale_no', 'pos_id', 'distributor_id',
        'agent_id', 'payment_kind', 'total_amount', 'paid_amount',
        'currency', 'exchange_rate', 'base_total', 'base_paid',
        'cash_box_id', 'debt_id', 'journal_entry_id',
        'commission_amount', 'discount_amount', 'status', 'sold_at',
        'note', 'idempotency_key',
    ];

    protected $casts = [
        'total_amount' => 'decimal:2',
        'discount_amount' => 'decimal:2',
        'paid_amount' => 'decimal:2',
        'exchange_rate' => 'decimal:6',
        'base_total' => 'decimal:2',
        'base_paid' => 'decimal:2',
        'commission_amount' => 'decimal:2',
        'sold_at' => 'datetime',
    ];

    public function items()
    {
        return $this->hasMany(AccSaleItem::class, 'sale_id');
    }

    public function pos()
    {
        return $this->belongsTo(AccPosPoint::class, 'pos_id');
    }

    public function distributor()
    {
        return $this->belongsTo(AccAgent::class, 'distributor_id');
    }

    public function agent()
    {
        return $this->belongsTo(AccAgent::class, 'agent_id');
    }

    public function box()
    {
        return $this->belongsTo(AccCashBox::class, 'cash_box_id');
    }

    public function debt()
    {
        return $this->belongsTo(AccDebt::class, 'debt_id');
    }

    public function entry()
    {
        return $this->belongsTo(AccJournalEntry::class, 'journal_entry_id');
    }

    /** The credit remainder still on the POS's receivable. */
    public function creditRemaining(): float
    {
        return max(0.0, (float) $this->total_amount - (float) $this->paid_amount);
    }
}
