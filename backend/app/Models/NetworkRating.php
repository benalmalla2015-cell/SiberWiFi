<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class NetworkRating extends Model
{
    protected $fillable = [
        'user_id', 'network_id', 'rating', 'review', 'owner_reply', 'replied_at',
    ];

    protected $casts = [
        'rating' => 'decimal:2',
    ];

    public function user() { return $this->belongsTo(User::class); }
    public function network() { return $this->belongsTo(Network::class); }
}
