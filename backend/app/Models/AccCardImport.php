<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Bulk card-import audit row — `file` uploads (CSV stock intake) and
 * `mikrotik` auto-sync batches both land here (PLAN §2.1).
 */
class AccCardImport extends Model
{
    protected $table = 'acc_card_imports';

    protected $fillable = [
        'network_owner_id', 'source', 'filename', 'category_id',
        'rows_count', 'imported_count', 'skipped_count',
        'status', 'errors', 'agent_id',
    ];

    protected $casts = [
        'errors' => 'array',
    ];

    public const STATUSES = ['processed', 'partial', 'failed'];
}
