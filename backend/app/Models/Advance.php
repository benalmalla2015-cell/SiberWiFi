<?php

namespace App\Models;

/**
 * A "سلفني" (advance) view over the transactions table: cards a customer
 * received without paying, to be settled from their next wallet top-up.
 * Shown to the admin in a dedicated Filament interface, separate from
 * regular sales, per the "لوحة تحكم منفصلة" requirement.
 */
class Advance extends Transaction
{
    protected $table = 'transactions';

    protected static function booted(): void
    {
        static::addGlobalScope('advance', function ($query) {
            $query->where('is_advance', true);
        });
    }
}
