<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A live RADIUS session on a host NAS (CYB-04), keyed by
 * (nas_identifier, session_id). Octet counters are cumulative as
 * reported by accounting records.
 */
class CyberSession extends Model
{
    protected $table = 'cyber_active_sessions';

    protected $fillable = [
        'subscriber_id', 'subscription_id', 'sim_no', 'nas_identifier',
        'nas_ip', 'session_id', 'started_at', 'last_seen_at',
        'input_octets', 'output_octets', 'status', 'close_reason',
        'coa_attempts', 'closed_at',
    ];

    protected $casts = [
        'started_at' => 'datetime',
        'last_seen_at' => 'datetime',
        'closed_at' => 'datetime',
        'input_octets' => 'integer',
        'output_octets' => 'integer',
    ];

    public function subscription()
    {
        return $this->belongsTo(CyberSubscription::class, 'subscription_id');
    }

    public function getTotalOctetsAttribute(): int
    {
        return (int) $this->input_octets + (int) $this->output_octets;
    }
}
