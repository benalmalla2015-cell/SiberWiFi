<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Region extends Model
{
    protected $fillable = [
        'name', 'name_en', 'type', 'currency', 'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function directorates() { return $this->hasMany(Directorate::class); }
    public function networks() { return $this->hasMany(Network::class); }
}
