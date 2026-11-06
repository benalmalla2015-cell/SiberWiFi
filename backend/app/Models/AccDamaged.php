<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Damaged/lost cards register row (PLAN §2.1). */
class AccDamaged extends Model
{
    protected $table = 'acc_damaged';

    protected $fillable = [
        'network_owner_id', 'category_id', 'qty', 'unit_cost',
        'reason', 'evidence_note', 'date', 'agent_id',
    ];

    protected $casts = [
        'qty' => 'decimal:2',
        'unit_cost' => 'decimal:4',
        'date' => 'date',
    ];

    public function category()
    {
        return $this->belongsTo(AccCardCategory::class, 'category_id');
    }
}
