<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A card/package purchase document. Written once inside the stock
 * transaction — the matching `in` movement and `purchase` journal
 * entry carry ref_type=acc_purchases/ref_id=id.
 */
class AccPurchase extends Model
{
    protected $table = 'acc_purchases';

    protected $fillable = [
        'network_owner_id', 'supplier_id', 'category_id', 'invoice_no',
        'qty', 'unit_price', 'currency', 'exchange_rate', 'total',
        'payment', 'date', 'agent_id', 'note',
    ];

    protected $casts = [
        'qty' => 'decimal:2',
        'unit_price' => 'decimal:2',
        'exchange_rate' => 'decimal:6',
        'total' => 'decimal:2',
        'date' => 'date',
    ];

    public const PAYMENTS = ['cash', 'credit'];

    public function supplier()
    {
        return $this->belongsTo(AccSupplier::class, 'supplier_id');
    }

    public function category()
    {
        return $this->belongsTo(AccCardCategory::class, 'category_id');
    }
}
