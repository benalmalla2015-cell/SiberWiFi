<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Storage;

/**
 * Registry row for one exported acc_* snapshot (ACC-12, PLAN §2.5).
 * The file itself lives on the local disk under
 * acc_backups/{network_owner_id}/{filename}.
 */
class AccBackup extends Model
{
    protected $table = 'acc_backups';

    protected $fillable = [
        'network_owner_id', 'filename', 'size', 'tables_count',
        'rows_count', 'checksum', 'created_by',
    ];

    /** Storage path relative to the local disk root. */
    public function storagePath(): string
    {
        return 'acc_backups/' . $this->network_owner_id . '/' . $this->filename;
    }

    public function fileExists(): bool
    {
        return Storage::disk('local')->exists($this->storagePath());
    }
}
