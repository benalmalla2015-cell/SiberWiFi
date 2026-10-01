<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Database\Factories\UserFactory;
use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use Spatie\Permission\Traits\HasRoles;

class User extends Authenticatable implements FilamentUser
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, HasRoles, Notifiable;

    public function canAccessPanel(Panel $panel): bool
    {
        return $this->type === 'admin';
    }

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'email',
        'phone',
        'password',
        'type',
        'region_type',
        'region_id',
        'directorate_id',
        'sub_directorate_id',
        'account_number',
        'device_id',
        'referral_code',
        'referred_by',
        'balance',
        'available_balance',
        'frozen_balance',
        'advance_balance',
        'is_active',
        'is_verified',
        'currency',
        'avatar',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_active' => 'boolean',
            'is_verified' => 'boolean',
            'balance' => 'decimal:2',
            'available_balance' => 'decimal:2',
            'frozen_balance' => 'decimal:2',
            'advance_balance' => 'decimal:2',
        ];
    }

    /**
     * "سلفني" (advance) eligibility:
     *  1) The customer must have at least one approved wallet top-up (i.e.
     *     is not a brand new customer who never charged their balance), and
     *  2) Their current spendable balance must be fully depleted (0). A
     *     customer who still has balance available must use it to buy cards
     *     normally; the advance service only kicks in once that balance runs
     *     out — otherwise, immediately after topping up (before spending it
     *     down), it also does not become eligible until the balance reaches
     *     zero again.
     */
    public function isEligibleForAdvance(): bool
    {
        $hasToppedUp = $this->walletLogs()
            ->where('type', 'credit')
            ->where(function ($query) {
                $query->whereNull('reference_type')
                    ->orWhereNotIn('reference_type', ['cashback', 'referral']);
            })
            ->exists();
        $hasCompletedWalletPurchase = $this->walletLogs()
            ->where('type', 'debit')
            ->where('reference_type', 'purchase')
            ->exists();

        return ($hasToppedUp || $hasCompletedWalletPurchase)
            && (float) $this->balance <= 0
            && (float) $this->available_balance <= 0;
    }

    public function region()
    {
        return $this->belongsTo(Region::class);
    }

    public function directorate()
    {
        return $this->belongsTo(Directorate::class);
    }

    public function subDirectorate()
    {
        return $this->belongsTo(SubDirectorate::class);
    }

    public function networkOwnerProfile()
    {
        return $this->hasOne(NetworkOwner::class, 'user_id');
    }

    public function networks()
    {
        return $this->hasMany(Network::class, 'user_id');
    }

    public function walletLogs()
    {
        return $this->hasMany(WalletLog::class, 'user_id');
    }

    public function transactions()
    {
        return $this->hasMany(Transaction::class, 'user_id');
    }

    /** Outstanding/settled "سلفني" advance transactions for this customer. */
    public function advances()
    {
        return $this->hasMany(Transaction::class, 'user_id')->where('is_advance', true);
    }

    public function fcmTokens()
    {
        return $this->hasMany(FcmToken::class, 'user_id');
    }

    /**
     * Total earnings for network owners from completed card sales.
     * Gross sales total (what customers paid) rather than the net
     * owner share, so إجمالي figures reflect the full sale amounts.
     */
    public function getTotalEarningsAttribute(): float
    {
        return (float) Transaction::whereIn('network_id', $this->networks()->pluck('id'))
            ->where('status', 'completed')
            ->sum('total_amount');
    }

    public function getAvatarUrlAttribute(): ?string
    {
        return $this->avatar ? asset('storage/' . $this->avatar) : null;
    }
}
