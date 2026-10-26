<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Append-only audit trail for accounting actions.
 * meta carries latency_ms + payload_hash (PLAN §2.5) to feed the
 * accountant-style performance report.
 */
class AccAuditLog extends Model
{
    protected $table = 'acc_audit_log';

    public $timestamps = false;

    protected $fillable = [
        'network_owner_id', 'agent_id', 'action', 'entity',
        'entity_id', 'meta', 'created_at',
    ];

    protected $casts = [
        'meta' => 'array',
        'created_at' => 'datetime',
    ];
}
