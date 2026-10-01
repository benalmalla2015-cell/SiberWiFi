<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PayoutRequest extends Model
{
    protected $fillable = [
        'request_number', 'user_id', 'amount', 'requested_amount', 'remaining_amount',
        'paid_amount', 'service_name', 'transaction_number',
        'status', 'paid_at', 'received_confirmed_at',
        'admin_notes', 'is_frozen',
        'payout_full_name', 'payout_provider', 'payout_account_number',
        'rejection_reason', 'processed_by',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'requested_amount' => 'decimal:2',
        'remaining_amount' => 'decimal:2',
        'paid_amount' => 'decimal:2',
        'paid_at' => 'datetime',
        'received_confirmed_at' => 'datetime',
        'is_frozen' => 'boolean',
    ];

    public function user() { return $this->belongsTo(User::class); }
}
