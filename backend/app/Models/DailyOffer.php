<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class DailyOffer extends Model
{
    protected $fillable = [
        'network_id', 'category_id', 'title', 'description',
        'discount_percent', 'discount_percentage', 'discounted_price',
        'starts_at', 'ends_at', 'start_date', 'end_date', 'is_active',
        'apply_to_all_categories', 'category_ids',
    ];

    protected $casts = [
        'discount_percent' => 'decimal:2',
        'discount_percentage' => 'decimal:2',
        'discounted_price' => 'decimal:2',
        'starts_at' => 'datetime',
        'start_date' => 'datetime',
        'end_date' => 'datetime',
        'ends_at' => 'datetime',
        'is_active' => 'boolean',
        'apply_to_all_categories' => 'boolean',
        'category_ids' => 'array',
    ];

    public function network() { return $this->belongsTo(Network::class); }
    public function category() { return $this->belongsTo(CardCategory::class, 'category_id'); }

    /**
     * Best currently-active offer for a network+category (highest discount).
     * Matches offers that apply to all categories, or list the category in
     * `category_ids`, or the legacy single `category_id` column.
     */
    public static function applicableFor(int $networkId, ?int $categoryId): ?self
    {
        return static::activeForNetwork($networkId)
            ->get()
            ->filter(fn (self $offer) => $offer->appliesToCategory($categoryId))
            ->sortByDesc(fn (self $offer) => $offer->effectiveDiscountPercent())
            ->first();
    }

    public static function activeForNetwork(int $networkId): \Illuminate\Database\Eloquent\Builder
    {
        $now = now();

        return static::where('network_id', $networkId)
            ->where('is_active', true)
            ->where(function ($query) use ($now) {
                $query->where(function ($modern) use ($now) {
                    $modern->whereNull('starts_at')->orWhere('starts_at', '<=', $now);
                })->where(function ($legacy) use ($now) {
                    $legacy->whereNotNull('starts_at')
                        ->orWhereNull('start_date')
                        ->orWhere('start_date', '<=', $now);
                });
            })
            ->where(function ($query) use ($now) {
                $query->where(function ($modern) use ($now) {
                    $modern->whereNull('ends_at')->orWhere('ends_at', '>=', $now);
                })->where(function ($legacy) use ($now) {
                    $legacy->whereNotNull('ends_at')
                        ->orWhereNull('end_date')
                        ->orWhere('end_date', '>=', $now);
                });
            });
    }

    /**
     * Pick the best offer for a category out of a preloaded collection —
     * used when listing many categories for one network (avoids N+1 and
     * JSON-contains queries per row).
     */
    public static function pickForCategory(iterable $offers, ?int $categoryId): ?self
    {
        $best = null;
        foreach ($offers as $offer) {
            if ($offer->appliesToCategory($categoryId)
                && ($best === null || $offer->effectiveDiscountPercent() > $best->effectiveDiscountPercent())) {
                $best = $offer;
            }
        }
        return $best;
    }

    public function appliesToCategory(?int $categoryId): bool
    {
        $categoryIds = array_map('intval', (array) ($this->category_ids ?? []));
        $hasCategoryScope = $this->category_id !== null || $categoryIds !== [];

        return (bool) $this->apply_to_all_categories
            || ! $hasCategoryScope
            || ($categoryId && (int) $this->category_id === $categoryId)
            || ($categoryId && in_array($categoryId, $categoryIds, true));
    }

    public function effectiveDiscountPercent(): float
    {
        $discountPercent = (float) $this->discount_percent;

        return $discountPercent > 0 ? $discountPercent : (float) ($this->discount_percentage ?? 0);
    }

    /** Discounted unit price in the network's native currency. */
    public function applyToUnitPrice(float $unitPrice): float
    {
        if ((float) $this->discounted_price > 0) {
            return min($unitPrice, (float) $this->discounted_price);
        }
        $discountPercent = $this->effectiveDiscountPercent();
        if ($discountPercent > 0) {
            return round($unitPrice * (1 - $discountPercent / 100), 2);
        }
        return $unitPrice;
    }

    protected static function booted(): void
    {
        static::created(function (DailyOffer $offer) {
            if (! $offer->is_active) {
                return;
            }

            try {
                $service = app(\App\Services\NotificationService::class);
                $networkName = $offer->network?->name ?? 'شبكة';
                $title = 'عرض جديد متاح';
                $body = "عرض '{$offer->title}' متاح الآن على {$networkName}";
                $data = ['type' => 'daily_offer', 'offer_id' => $offer->id, 'network_id' => $offer->network_id];

                $network = $offer->network;
                if ($network && $network->region_id) {
                    User::where('type', 'client')
                        ->where('region_id', $network->region_id)
                        ->chunkById(100, function ($clients) use ($service, $title, $body, $data) {
                            foreach ($clients as $client) {
                                $service->send($client, $title, $body, $data);
                            }
                        });
                } else {
                    User::where('type', 'client')
                        ->chunkById(100, function ($clients) use ($service, $title, $body, $data) {
                            foreach ($clients as $client) {
                                $service->send($client, $title, $body, $data);
                            }
                        });
                }
            } catch (\Throwable $e) {
                \Log::warning('DailyOffer notification failed: ' . $e->getMessage());
            }
        });
    }
}
