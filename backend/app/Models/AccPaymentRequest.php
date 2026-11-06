<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Manual transfer request for an accounting plan (ACC-11, PLAN §6.1)
 * — mirrors MikrotikPaymentRequest, tenant-keyed. `user_id` is the
 * acting submitter (owner or admin agent) for admin review.
 */
class AccPaymentRequest extends Model
{
    protected $table = 'acc_payment_requests';

    protected $fillable = [
        'network_owner_id', 'user_id', 'plan_id', 'amount', 'sender_name',
        'bank_account_id', 'transfer_receipt_number',
        'receipt_image', 'status',
        'admin_note', 'reviewed_by', 'reviewed_at',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'reviewed_at' => 'datetime',
    ];

    public function owner()
    {
        return $this->belongsTo(User::class, 'network_owner_id');
    }

    public function user() { return $this->belongsTo(User::class); }
    public function plan() { return $this->belongsTo(AccPlan::class); }
    public function bankAccount() { return $this->belongsTo(BankAccount::class); }
    public function reviewer() { return $this->belongsTo(User::class, 'reviewed_by'); }

    public function subscription()
    {
        return $this->hasOne(AccSubscription::class, 'payment_request_id');
    }
}
