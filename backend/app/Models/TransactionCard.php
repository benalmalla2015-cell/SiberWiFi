<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TransactionCard extends Model
{
    protected $fillable = [
        'transaction_id',
        'card_id',
    ];

    public function transaction()
    {
        return $this->belongsTo(Transaction::class);
    }

    public function card()
    {
        return $this->belongsTo(Card::class);
    }
}
