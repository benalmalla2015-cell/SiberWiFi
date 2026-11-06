<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CyberDocument extends Model
{
    protected $fillable = [
        'subscriber_id', 'document_type', 'front_path', 'back_path',
        'review_status', 'reviewed_at',
    ];

    protected $casts = [
        'reviewed_at' => 'datetime',
    ];

    public function subscriber() { return $this->belongsTo(CyberSubscriber::class, 'subscriber_id'); }
}
