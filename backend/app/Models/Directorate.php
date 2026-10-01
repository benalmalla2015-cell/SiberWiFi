<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Directorate extends Model
{
    protected $fillable = [
        'region_id', 'name', 'name_en', 'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function region() { return $this->belongsTo(Region::class); }
    public function networks() { return $this->hasMany(Network::class); }
    public function subDirectorates() { return $this->hasMany(SubDirectorate::class); }
}
