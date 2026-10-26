<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TopupOrder extends Model
{
    protected $fillable = [
        'user_id', 'service_code', 'account', 'target', 'amount', 'fee',
        'total_charged', 'provider_price', 'transid', 'provider_ref_id',
        'status', 'result_code', 'result_desc', 'request_payload',
        'provider_response', 'refunded',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'fee' => 'decimal:2',
        'total_charged' => 'decimal:2',
        'provider_price' => 'decimal:2',
        'request_payload' => 'array',
        'provider_response' => 'array',
        'refunded' => 'boolean',
    ];

    public function user() { return $this->belongsTo(User::class); }
}
