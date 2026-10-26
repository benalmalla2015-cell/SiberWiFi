<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Card extends Model
{
    protected $fillable = [
        'network_id', 'category_id', 'card_number', 'serial', 'code',
        'status', 'sold_to', 'sold_at', 'transaction_id',
        'source', 'router_id', 'meta',
    ];

    protected $casts = [
        'sold_at' => 'datetime',
        'meta' => 'array',
    ];

    public function network() { return $this->belongsTo(Network::class); }
    public function category() { return $this->belongsTo(CardCategory::class); }
    public function buyer() { return $this->belongsTo(User::class, 'sold_to'); }
    public function transaction() { return $this->belongsTo(Transaction::class); }
    public function router() { return $this->belongsTo(MikrotikRouter::class, 'router_id'); }

    public function scopeAvailable($q) { return $q->where('status', 'available'); }
    public function scopeSold($q) { return $q->where('status', 'sold'); }
}
