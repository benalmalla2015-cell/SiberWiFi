<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CashbackSetting extends Model
{
    protected $fillable = ['name', 'buy_count', 'cashback_percent', 'min_amount', 'is_global', 'network_id', 'category_id', 'is_active'];
    protected $casts    = [
        'buy_count'          => 'integer',
        'cashback_percent'   => 'decimal:2',
        'min_amount'         => 'decimal:2',
        'is_global'          => 'boolean',
        'is_active'          => 'boolean',
    ];

    public function network(): BelongsTo
    {
        return $this->belongsTo(Network::class);
    }
}
