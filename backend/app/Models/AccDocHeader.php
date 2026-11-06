<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Printed-document header of the tenant — one row per owner
 * (ACC-12, PLAN §2.5). Consumed by every printable accounting
 * document; `logo_path` is a private storage path streamed through
 * GET /doc-header/logo.
 */
class AccDocHeader extends Model
{
    protected $table = 'acc_doc_header';

    protected $fillable = [
        'network_owner_id', 'business_name', 'subtitle', 'phone',
        'address', 'footer_text', 'show_logo', 'logo_path',
    ];

    protected $casts = [
        'show_logo' => 'boolean',
    ];
}
