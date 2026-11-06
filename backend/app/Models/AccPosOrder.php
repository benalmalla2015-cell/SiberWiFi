<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * POS bundle order (PLAN §2.2). Status machine:
 *   pending → approved  (AccPosOrderService::approve — atomic post)
 *   pending → rejected  (AccPosOrderService::reject — no ledger effects)
 * Decided orders are immutable; a wrong approval is corrected by a
 * journal reversal, never by editing this row.
 */
class AccPosOrder extends Model
{
    protected $table = 'acc_pos_orders';

    protected $fillable = [
        'network_owner_id', 'order_no', 'pos_id', 'distributor_id',
        'requested_by', 'status', 'total_amount', 'discount_amount',
        'points_total', 'approved_by', 'approved_at', 'reject_reason',
        'note', 'idempotency_key',
    ];

    protected $casts = [
        'total_amount' => 'decimal:2',
        'discount_amount' => 'decimal:2',
        'points_total' => 'decimal:2',
        'approved_at' => 'datetime',
    ];

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_REJECTED = 'rejected';

    public const STATUSES = [
        self::STATUS_PENDING,
        self::STATUS_APPROVED,
        self::STATUS_REJECTED,
    ];

    public function items()
    {
        return $this->hasMany(AccPosOrderItem::class, 'order_id');
    }

    public function pos()
    {
        return $this->belongsTo(AccPosPoint::class, 'pos_id');
    }

    public function distributor()
    {
        return $this->belongsTo(AccAgent::class, 'distributor_id');
    }

    public function requestedBy()
    {
        return $this->belongsTo(AccAgent::class, 'requested_by');
    }

    public function approvedBy()
    {
        return $this->belongsTo(User::class, 'approved_by');
    }

    public function isPending(): bool
    {
        return $this->status === self::STATUS_PENDING;
    }
}
