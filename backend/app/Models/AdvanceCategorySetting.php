<?php

namespace App\Models;

/**
 * A view over card_categories limited to those a network owner has
 * requested "سلفني" (advance) support for. Used by the admin Filament
 * resource that approves/rejects these requests.
 */
class AdvanceCategorySetting extends CardCategory
{
    protected $table = 'card_categories';

    protected static function booted(): void
    {
        static::addGlobalScope('advance_request', function ($query) {
            $query->where('advance_status', '!=', 'none');
        });
    }
}
