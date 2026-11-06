<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Immutable stock ledger row — never updated or deleted (PLAN §2.1).
 * qty is signed: positive = stock in, negative = stock out.
 */
class AccStockMovement extends Model
{
    protected $table = 'acc_stock_movements';

    /** The log is append-only — no updated_at column. */
    public const UPDATED_AT = null;

    protected $fillable = [
        'network_owner_id', 'category_id', 'type', 'qty', 'unit_cost',
        'ref_type', 'ref_id', 'agent_id', 'note', 'created_at',
    ];

    protected $casts = [
        'qty' => 'decimal:2',
        'unit_cost' => 'decimal:4',
        'created_at' => 'datetime',
    ];

    public const TYPES = [
        'in', 'out', 'adjust', 'sale', 'return', 'damaged', 'order_fill',
    ];

    public function category()
    {
        return $this->belongsTo(AccCardCategory::class, 'category_id');
    }
}
