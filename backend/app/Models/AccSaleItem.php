<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One line of an acc_sales document — name/price/cost are
 * snapshotted at posting (same convention as acc_pos_order_items).
 */
class AccSaleItem extends Model
{
    protected $table = 'acc_sale_items';

    protected $fillable = [
        'sale_id', 'category_id', 'category_name', 'qty',
        'unit_price', 'unit_cost', 'line_total',
    ];

    protected $casts = [
        'unit_price' => 'decimal:2',
        'unit_cost' => 'decimal:2',
        'line_total' => 'decimal:2',
    ];

    public function sale()
    {
        return $this->belongsTo(AccSale::class, 'sale_id');
    }

    public function category()
    {
        return $this->belongsTo(AccCardCategory::class, 'category_id');
    }
}
