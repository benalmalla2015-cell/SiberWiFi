<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MikrotikRouter extends Model
{
    protected $fillable = [
        'user_id', 'network_id', 'name', 'host', 'api_port', 'username',
        'api_password', 'identity', 'board_name', 'os_version',
        'hotspot_users_count', 'hotspot_active_count', 'uptime',
        'last_seen_at',
    ];

    protected $hidden = ['api_password'];

    protected $casts = [
        'api_password' => 'encrypted',
        'last_seen_at' => 'datetime',
    ];

    public function owner() { return $this->belongsTo(User::class, 'user_id'); }
    public function network() { return $this->belongsTo(Network::class); }
    public function cards() { return $this->hasMany(Card::class, 'router_id'); }
}
