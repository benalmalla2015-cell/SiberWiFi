<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

/**
 * A distributor's commission for one calendar month (PLAN §2.4).
 * accrue() is the single write path — an atomic upsert inside the
 * caller's own DB transaction, so a commission can never post
 * without its document (or post twice on a replay).
 */
class AccCommission extends Model
{
    protected $table = 'acc_commissions';

    public const STATUS_ACCRUED = 'accrued';
    public const STATUS_PAID = 'paid';

    protected $fillable = [
        'network_owner_id', 'distributor_id', 'period',
        'sales_amount', 'commission_amount', 'status',
        'paid_at', 'paid_by', 'note',
    ];

    protected $casts = [
        'sales_amount' => 'decimal:2',
        'commission_amount' => 'decimal:2',
        'paid_at' => 'datetime',
    ];

    /**
     * Fold a document's commission into the distributor's period
     * row. Called inside the document's DB transaction — a racing
     * second writer waits on the unique-key row lock.
     *
     * @param  string  $period  YYYY-MM
     */
    public static function accrue(
        int $ownerId,
        int $distributorId,
        string $period,
        float $salesAmount,
        float $commissionAmount
    ): self {
        $row = static::where('network_owner_id', $ownerId)
            ->where('distributor_id', $distributorId)
            ->where('period', $period)
            ->lockForUpdate()
            ->first();

        if ($row === null) {
            return static::create([
                'network_owner_id' => $ownerId,
                'distributor_id' => $distributorId,
                'period' => $period,
                'sales_amount' => round($salesAmount, 2),
                'commission_amount' => round($commissionAmount, 2),
                'status' => self::STATUS_ACCRUED,
            ]);
        }

        // A paid period is closed — corrections belong to a new row.
        if ($row->status === self::STATUS_ACCRUED) {
            $row->sales_amount = round((float) $row->sales_amount + $salesAmount, 2);
            $row->commission_amount = round((float) $row->commission_amount + $commissionAmount, 2);
            $row->save();
        }

        return $row;
    }

    public function distributor()
    {
        return $this->belongsTo(AccAgent::class, 'distributor_id');
    }
}
