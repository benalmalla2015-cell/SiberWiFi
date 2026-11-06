<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Returns register row (PLAN §2.1).
 *   purchase_return → cards leave stock back to the supplier (qty -)
 *   sale_return | card_return → cards re-enter stock (qty +)
 */
class AccReturn extends Model
{
    protected $table = 'acc_returns';

    protected $fillable = [
        'network_owner_id', 'kind', 'ref_type', 'ref_id', 'category_id',
        'qty', 'amount', 'reason', 'date', 'agent_id',
    ];

    protected $casts = [
        'qty' => 'decimal:2',
        'amount' => 'decimal:2',
        'date' => 'date',
    ];

    public const KINDS = ['purchase_return', 'sale_return', 'card_return'];

    /** Kinds that move stock back IN. */
    public const IN_KINDS = ['sale_return', 'card_return'];

    public function category()
    {
        return $this->belongsTo(AccCardCategory::class, 'category_id');
    }
}
