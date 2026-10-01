<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Report extends Model
{
    protected $fillable = [
        'user_id', 'network_id', 'type',
        'subject', 'description', 'message', 'status',
        'admin_reply', 'replied_at', 'replied_by',
    ];

    protected $casts = [
        'replied_at' => 'datetime',
    ];

    public function user() { return $this->belongsTo(User::class); }
    public function network() { return $this->belongsTo(Network::class); }
}
