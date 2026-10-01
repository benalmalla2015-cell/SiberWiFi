<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Network extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = [
        'user_id', 'region_id', 'directorate_id', 'sub_directorate_id', 'name', 'slug', 'logo',
        'cover_image', 'background_image', 'url', 'description', 'phone',
        'commission_rate', 'supports_credit', 'average_rating', 'ratings_count',
        'sales_count', 'views_count', 'status', 'rejection_reason',
        'is_featured', 'approved_at', 'approved_by', 'code',
    ];

    protected static function booted(): void
    {
        static::created(function (self $network) {
            if (empty($network->code)) {
                $network->code = 'SW-' . str_pad((string) $network->id, 6, '0', STR_PAD_LEFT);
                $network->saveQuietly();
            }
        });
    }

    protected function casts(): array
    {
        return [
            'supports_credit' => 'boolean',
            'is_featured'     => 'boolean',
            'approved_at'     => 'datetime',
            'average_rating'  => 'decimal:2',
            'commission_rate' => 'decimal:2',
        ];
    }

    public function owner(): BelongsTo       { return $this->belongsTo(User::class, 'user_id'); }
    public function region(): BelongsTo      { return $this->belongsTo(Region::class); }
    public function directorate(): BelongsTo { return $this->belongsTo(Directorate::class); }
    public function subDirectorate(): BelongsTo { return $this->belongsTo(SubDirectorate::class); }
    public function approvedBy(): BelongsTo  { return $this->belongsTo(User::class, 'approved_by'); }
    public function cardCategories(): HasMany { return $this->hasMany(CardCategory::class); }
    public function cards(): HasMany          { return $this->hasMany(Card::class); }
    public function transactions(): HasMany   { return $this->hasMany(Transaction::class); }
    public function ratings(): HasMany        { return $this->hasMany(NetworkRating::class); }
    public function reports(): HasMany        { return $this->hasMany(Report::class); }
    public function favorites(): HasMany      { return $this->hasMany(Favorite::class); }
    public function dailyOffers(): HasMany    { return $this->hasMany(DailyOffer::class); }
    public function chargingPoints(): HasMany { return $this->hasMany(ChargingPoint::class); }

    public function scopeActive($query)   { return $query->where('status', 'active'); }
    public function scopePending($query)  { return $query->where('status', 'pending'); }
    public function scopeFeatured($query) { return $query->where('is_featured', true); }

    public function getLogoUrlAttribute(): ?string
    {
        return $this->logo ? asset('storage/' . $this->logo) : null;
    }

    public function getCoverImageUrlAttribute(): ?string
    {
        return $this->cover_image ? asset('storage/' . $this->cover_image) : null;
    }

    public function getBackgroundImageUrlAttribute(): ?string
    {
        return $this->background_image ? asset('storage/' . $this->background_image) : null;
    }

    /**
     * Keep the `supports_credit` flag (used by the customer app "سلفني"
     * filter) in sync with whether this network actually has at least one
     * admin-approved advance-enabled category with remaining capacity.
     */
    public function hasAvailableAdvance(): bool
    {
        if (array_key_exists('has_available_advance', $this->attributes)) {
            return (bool) $this->attributes['has_available_advance'];
        }

        return $this->cardCategories()
            ->where('is_active', true)
            ->where('advance_enabled', true)
            ->where('advance_status', 'approved')
            ->whereColumn('advance_used_count', '<', 'advance_max_cards')
            ->exists();
    }

    public function recalculateAdvanceSupport(): void
    {
        $hasAdvance = $this->hasAvailableAdvance();

        if ((bool) $this->supports_credit !== $hasAdvance) {
            $this->update(['supports_credit' => $hasAdvance]);
        }
    }
}
