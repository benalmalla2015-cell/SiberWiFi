<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Per-tenant running stock balance per category. Rows are created
 * lazily by AccStockService on the first movement of a category.
 */
class AccStock extends Model
{
    protected $table = 'acc_stock';

    protected $fillable = [
        'network_owner_id', 'category_id', 'qty', 'avg_cost',
    ];

    protected $casts = [
        'qty' => 'decimal:2',
        'avg_cost' => 'decimal:4',
    ];

    public function category()
    {
        return $this->belongsTo(AccCardCategory::class, 'category_id');
    }
}
