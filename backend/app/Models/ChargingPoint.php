<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ChargingPoint extends Model
{
    protected $fillable = [
        'network_id', 'user_id', 'name', 'phone', 'location',
        'latitude', 'longitude', 'working_hours', 'is_active', 'is_approved',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'is_approved' => 'boolean',
        'latitude' => 'decimal:8',
        'longitude' => 'decimal:8',
    ];

    public function network() { return $this->belongsTo(Network::class); }
    public function user() { return $this->belongsTo(User::class); }

    protected static function booted(): void
    {
        static::updated(function (ChargingPoint $point) {
            if ($point->is_approved && ! $point->getOriginal('is_approved')) {
                try {
                    $owner = $point->network?->owner;
                    if ($owner) {
                        app(\App\Services\NotificationService::class)->send(
                            $owner,
                            'نقطة شحن معتمدة',
                            "تم اعتماد نقطة الشحن '{$point->name}' لشبكتك.",
                            ['type' => 'charging_point_approved', 'point_id' => $point->id, 'network_id' => $point->network_id]
                        );
                    }
                } catch (\Throwable $e) {
                    \Log::warning('ChargingPoint notification failed: ' . $e->getMessage());
                }
            }
        });
    }
}
