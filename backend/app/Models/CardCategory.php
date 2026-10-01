<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CardCategory extends Model
{
    protected $fillable = [
        'network_id', 'name', 'speed', 'duration',
        'duration_unit', 'price', 'value', 'description', 'is_active',
        'advance_enabled', 'advance_max_cards', 'advance_max_per_customer',
        'advance_status',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'price' => 'decimal:2',
        'value' => 'decimal:2',
        'duration' => 'integer',
        'advance_enabled' => 'boolean',
        'advance_max_cards' => 'integer',
        'advance_max_per_customer' => 'integer',
        'advance_used_count' => 'integer',
    ];

    public function network() { return $this->belongsTo(Network::class); }
    public function cards() { return $this->hasMany(Card::class, 'category_id'); }
}
