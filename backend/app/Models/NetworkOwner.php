<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class NetworkOwner extends Model
{
    protected $fillable = [
        'user_id', 'business_name', 'national_id',
        'payout_full_name', 'payout_provider', 'payout_account_number',
        'bank_name', 'bank_account', 'notes',
        'is_approved', 'approved_at', 'approved_by',
    ];

    protected $casts = [
        'is_approved' => 'boolean',
        'approved_at' => 'datetime',
    ];

    public function user() { return $this->belongsTo(User::class); }
    public function networks() { return $this->hasMany(Network::class, 'user_id', 'user_id'); }

    protected static function booted(): void
    {
        static::updated(function (NetworkOwner $owner) {
            if ($owner->is_approved && ! $owner->getOriginal('is_approved')) {
                try {
                    if ($owner->user) {
                        app(\App\Services\NotificationService::class)->send(
                            $owner->user,
                            'تمت الموافقة على حسابك',
                            'تم اعتماد حسابك كصاحب شبكة. يمكنك الآن إدارة شبكاتك وإضافة الكروت.',
                            ['type' => 'network_owner_approved', 'owner_id' => $owner->id]
                        );
                    }
                } catch (\Throwable $e) {
                    \Log::warning('NetworkOwner approval notification failed: ' . $e->getMessage());
                }
            }

            // Sync payout data to pending payout requests when payout fields are updated
            $payoutFields = ['payout_full_name', 'payout_provider', 'payout_account_number'];
            $payoutFieldsChanged = false;
            foreach ($payoutFields as $field) {
                if ($owner->isDirty($field)) {
                    $payoutFieldsChanged = true;
                    break;
                }
            }

            if ($payoutFieldsChanged) {
                try {
                    \App\Models\PayoutRequest::where('user_id', $owner->user_id)
                        ->whereIn('status', ['pending', 'approved'])
                        ->update([
                            'payout_full_name' => $owner->payout_full_name,
                            'payout_provider' => $owner->payout_provider,
                            'payout_account_number' => $owner->payout_account_number,
                        ]);
                    \Log::info('Payout data synced to pending requests for user ' . $owner->user_id);
                } catch (\Throwable $e) {
                    \Log::warning('Failed to sync payout data to requests: ' . $e->getMessage());
                }
            }
        });
    }
}
