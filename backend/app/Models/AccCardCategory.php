<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Accounting card category (PLAN §2.1) — the acc-side catalog row
 * that stock, purchases and POS orders reference. `card_category_id`
 * binds it to the platform catalog for the MikroTik auto-sync.
 */
class AccCardCategory extends Model
{
    protected $table = 'acc_card_categories';

    protected $fillable = [
        'network_owner_id', 'name', 'sell_price', 'cost_price',
        'unit_label', 'source_binding', 'card_category_id',
        'sort_order', 'is_active',
    ];

    protected $casts = [
        'sell_price' => 'decimal:2',
        'cost_price' => 'decimal:2',
        'is_active' => 'boolean',
        'sort_order' => 'integer',
    ];

    public const BINDINGS = ['platform', 'mikrotik', 'any'];

    public function stock()
    {
        return $this->hasOne(AccStock::class, 'category_id');
    }

    public function platformCategory()
    {
        return $this->belongsTo(CardCategory::class, 'card_category_id');
    }
}
