<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Profit withdrawal request (PLAN §2.2). Status machine:
 *   pending → approved → paid   (management decide path)
 *   pending → rejected          (profit hold refunded)
 *   pending → cancelled         (requester cancels, hold refunded)
 * Decided rows are immutable; a wrong payout is corrected by a
 * journal reversal, never by editing this row.
 */
class AccWithdrawal extends Model
{
    protected $table = 'acc_withdrawals';

    protected $fillable = [
        'network_owner_id', 'requester_type', 'requester_id',
        'requested_by', 'amount', 'status',
        'receiver_name', 'receipt_no', 'note', 'review_note',
        'reviewed_by', 'reviewed_at', 'paid_at',
        'cash_box_id', 'journal_entry_id', 'idempotency_key',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'reviewed_at' => 'datetime',
        'paid_at' => 'datetime',
    ];

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_PAID = 'paid';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_CANCELLED = 'cancelled';

    public const STATUSES = [
        self::STATUS_PENDING,
        self::STATUS_APPROVED,
        self::STATUS_PAID,
        self::STATUS_REJECTED,
        self::STATUS_CANCELLED,
    ];

    public const REQUESTER_TYPES = ['pos', 'distributor'];

    public function pos()
    {
        return $this->belongsTo(AccPosPoint::class, 'requester_id');
    }

    public function requestedBy()
    {
        return $this->belongsTo(AccAgent::class, 'requested_by');
    }

    public function box()
    {
        return $this->belongsTo(AccCashBox::class, 'cash_box_id');
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function isPending(): bool
    {
        return $this->status === self::STATUS_PENDING;
    }
}
