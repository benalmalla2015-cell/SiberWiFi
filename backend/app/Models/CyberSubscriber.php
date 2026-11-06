<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class CyberSubscriber extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'sim_no', 'full_name', 'directorate_id', 'sub_directorate_id', 'status',
    ];

    public function documents() { return $this->hasMany(CyberDocument::class, 'subscriber_id'); }
    public function identity() { return $this->hasOne(CyberIdentity::class, 'subscriber_id'); }
    public function directorate() { return $this->belongsTo(Directorate::class); }
    public function subDirectorate() { return $this->belongsTo(SubDirectorate::class); }
}
