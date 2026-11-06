<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CyberIdentity extends Model
{
    protected $fillable = [
        'subscriber_id', 'certificate_serial', 'device_id', 'status',
        'fcm_token',
    ];

    public function subscriber() { return $this->belongsTo(CyberSubscriber::class, 'subscriber_id'); }
}
