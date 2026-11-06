<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Card/package supplier (PLAN §2.1). */
class AccSupplier extends Model
{
    protected $table = 'acc_suppliers';

    protected $fillable = [
        'network_owner_id', 'name', 'phone', 'note',
    ];

    public function purchases()
    {
        return $this->hasMany(AccPurchase::class, 'supplier_id');
    }
}
