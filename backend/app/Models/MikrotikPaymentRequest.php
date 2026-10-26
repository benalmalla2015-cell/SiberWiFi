<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MikrotikPaymentRequest extends Model
{
    protected $fillable = [
        'user_id', 'plan_id', 'amount', 'sender_name',
        'bank_account_id', 'transfer_receipt_number',
        'receipt_image', 'status',
        'admin_note', 'reviewed_by', 'reviewed_at',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'reviewed_at' => 'datetime',
    ];

    public function user() { return $this->belongsTo(User::class); }
    public function plan() { return $this->belongsTo(MikrotikPlan::class); }
    public function bankAccount() { return $this->belongsTo(BankAccount::class); }
    public function reviewer() { return $this->belongsTo(User::class, 'reviewed_by'); }

    public function subscription()
    {
        return $this->hasOne(MikrotikSubscription::class, 'payment_request_id');
    }
}
