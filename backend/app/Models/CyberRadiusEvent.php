<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One ingested RADIUS ledger record (CYB-04). The unique
 * (source_file, source_offset) pair deduplicates the engine's
 * at-least-once delivery.
 */
class CyberRadiusEvent extends Model
{
    protected $table = 'cyber_radius_events';

    protected $fillable = [
        'source_file', 'source_offset', 'type', 'sim_no',
        'session_id', 'payload', 'processed_at',
    ];

    protected $casts = [
        'payload' => 'array',
        'processed_at' => 'datetime',
    ];
}
