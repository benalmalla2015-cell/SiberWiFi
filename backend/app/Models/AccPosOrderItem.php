<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One bundle line of a POS order. Prices/costs are snapshots taken
 * at submission — the order stays self-describing even if the
 * ACC-02 catalog row is edited or removed later.
 */
class AccPosOrderItem extends Model
{
    protected $table = 'acc_pos_order_items';

    protected $fillable = [
        'order_id', 'category_id', 'category_name',
        'qty', 'unit_price', 'unit_cost', 'line_total',
    ];

    protected $casts = [
        'qty' => 'integer',
        'unit_price' => 'decimal:2',
        'unit_cost' => 'decimal:2',
        'line_total' => 'decimal:2',
    ];

    public function order()
    {
        return $this->belongsTo(AccPosOrder::class, 'order_id');
    }
}
