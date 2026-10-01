<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WalletLog extends Model
{
    protected $fillable = [
        'user_id', 'counterparty_user_id', 'type', 'amount',
        'balance_before', 'balance_after',
        'description', 'reference_type', 'reference_id',
        'bank_account_id', 'transfer_receipt_number', 'sender_name',
        'receipt_image',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'balance_before' => 'decimal:2',
        'balance_after' => 'decimal:2',
    ];

    public function user() { return $this->belongsTo(User::class); }

    public function counterparty() { return $this->belongsTo(User::class, 'counterparty_user_id'); }

    public function bankAccount() { return $this->belongsTo(BankAccount::class); }
}
