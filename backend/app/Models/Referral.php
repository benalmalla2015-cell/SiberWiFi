<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Referral extends Model
{
    use \Illuminate\Database\Eloquent\Factories\HasFactory;

    protected $fillable = [
        'referrer_id', 'referred_id', 'transaction_id',
        'commission_amount', 'commission_percentage', 'is_paid', 'paid_at',
    ];
    protected $casts = [
        'is_paid'             => 'boolean',
        'paid_at'             => 'datetime',
        'commission_amount'   => 'decimal:2',
        'commission_percentage' => 'decimal:2',
    ];

    public function referrer()    { return $this->belongsTo(\App\Models\User::class, 'referrer_id'); }
    public function referred()    { return $this->belongsTo(\App\Models\User::class, 'referred_id'); }
    public function transaction() { return $this->belongsTo(\App\Models\Transaction::class); }
}
