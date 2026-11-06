<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Instant card-for-points redemption (PLAN §2.2). Written already
 * `completed` inside the transaction that spends the points, moves
 * the stock and posts the journal — there is no pending state to
 * babysit.
 */
class AccCardExchange extends Model
{
    protected $table = 'acc_card_exchanges';

    protected $fillable = [
        'network_owner_id', 'pos_id', 'category_id', 'category_name',
        'qty', 'unit_price', 'points_spent', 'status',
        'agent_id', 'journal_entry_id', 'note', 'idempotency_key',
    ];

    protected $casts = [
        'qty' => 'integer',
        'unit_price' => 'decimal:2',
        'points_spent' => 'decimal:2',
    ];

    public const STATUS_COMPLETED = 'completed';

    public function pos()
    {
        return $this->belongsTo(AccPosPoint::class, 'pos_id');
    }

    public function category()
    {
        return $this->belongsTo(AccCardCategory::class, 'category_id');
    }

    public function agent()
    {
        return $this->belongsTo(AccAgent::class, 'agent_id');
    }
}
