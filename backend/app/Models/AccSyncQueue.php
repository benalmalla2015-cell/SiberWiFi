<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One queued sync operation (ACC-12, PLAN §2.5).
 *
 * pending → sent        — the normal offline → online path.
 * pending → needs_review — dispatch failed; retry or discard from
 *                          the sync center.
 */
class AccSyncQueue extends Model
{
    protected $table = 'acc_sync_queue';

    public const STATUS_PENDING = 'pending';

    public const STATUS_SENT = 'sent';

    public const STATUS_NEEDS_REVIEW = 'needs_review';

    public const STATUSES = [
        self::STATUS_PENDING,
        self::STATUS_SENT,
        self::STATUS_NEEDS_REVIEW,
    ];

    protected $fillable = [
        'network_owner_id', 'client_op_id', 'op_type', 'payload',
        'status', 'attempts', 'last_error', 'result', 'sent_at',
    ];

    protected $casts = [
        'payload' => 'array',
        'result' => 'array',
        'sent_at' => 'datetime',
    ];
}
