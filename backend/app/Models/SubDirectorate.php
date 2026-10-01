<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class SubDirectorate extends Model
{
    protected $fillable = [
        'directorate_id', 'name', 'name_en', 'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function directorate(): BelongsTo { return $this->belongsTo(Directorate::class); }
    public function networks(): HasMany       { return $this->hasMany(Network::class); }
}
