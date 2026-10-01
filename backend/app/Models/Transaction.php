<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Transaction extends Model
{
    protected $fillable = [
        'transaction_number', 'user_id', 'network_id',
        'card_id', 'category_id', 'quantity',
        'unit_price', 'total_amount', 'discount_amount',
        'commission_amount', 'network_owner_amount', 'cashback_amount',
        'balance_before', 'balance_after', 'payment_method',
        'status', 'notes',
        'is_advance', 'advance_status', 'repaid_amount', 'repaid_at',
        'network_currency', 'buyer_currency', 'native_amount', 'exchange_rate_applied',
    ];

    protected $casts = [
        'quantity' => 'integer',
        'unit_price' => 'decimal:2',
        'total_amount' => 'decimal:2',
        'discount_amount' => 'decimal:2',
        'commission_amount' => 'decimal:2',
        'network_owner_amount' => 'decimal:2',
        'cashback_amount' => 'decimal:2',
        'balance_before' => 'decimal:2',
        'balance_after' => 'decimal:2',
        'is_advance' => 'boolean',
        'repaid_amount' => 'decimal:2',
        'repaid_at' => 'datetime',
    ];

    public function user() { return $this->belongsTo(User::class); }
    public function network() { return $this->belongsTo(Network::class); }
    public function card() { return $this->belongsTo(Card::class); }
    public function category() { return $this->belongsTo(CardCategory::class); }
    public function transactionCards() { return $this->hasMany(TransactionCard::class); }

    public function scopeAdvances($query) { return $query->where('is_advance', true); }
    public function scopeOutstandingAdvances($query)
    {
        return $query->where('is_advance', true)->whereIn('advance_status', ['outstanding', 'partially_repaid']);
    }

    /** Amount still owed by the customer for this advance transaction. */
    public function getAdvanceRemainingAttribute(): float
    {
        if (!$this->is_advance) {
            return 0;
        }

        return max(0, (float) $this->total_amount - (float) $this->repaid_amount);
    }
}
