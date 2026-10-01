<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Cache;

class MaintenanceMode extends Model
{
    use HasFactory;

    protected $fillable = [
        'app',
        'is_active',
        'title',
        'description',
        'image',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function getImageUrlAttribute(): ?string
    {
        if (!$this->image || !preg_match('#^maintenance_images/[a-zA-Z0-9._-]+$#', $this->image)) {
            return null;
        }

        return asset('storage/' . $this->image);
    }

    public static function isActiveFor(string $app): bool
    {
        return Cache::remember("maintenance_mode:{$app}", 60, function () use ($app) {
            return static::where('app', $app)->where('is_active', true)->exists();
        });
    }

    public static function getFor(string $app): ?self
    {
        return Cache::remember("maintenance_mode_data:{$app}", 60, function () use ($app) {
            return static::where('app', $app)->where('is_active', true)->first();
        });
    }

    public static function clearCache(string $app): void
    {
        Cache::forget("maintenance_mode:{$app}");
        Cache::forget("maintenance_mode_data:{$app}");
    }

    public function notifyUsers(): void
    {
        try {
            $service = app(\App\Services\NotificationService::class);

            $query = User::query()
                ->where('is_active', true)
                ->whereHas('fcmTokens', function ($q) {
                    $q->where('is_active', true)
                      ->where(function ($sq) {
                          $sq->whereNull('app')->orWhere('app', $this->app);
                      });
                });

            if ($this->app === 'customer_app') {
                $query->where('type', 'client');
            } elseif ($this->app === 'network_owner_app') {
                $query->where('type', 'network_owner');
            }

            foreach ($query->cursor() as $user) {
                $service->send($user, $this->title, $this->description ?? '', [
                    'type' => 'maintenance_mode',
                    'app'  => $this->app,
                    'is_active' => $this->is_active ? '1' : '0',
                    'image' => $this->image_url,
                ], $this->image_url);
            }
        } catch (\Throwable $e) {
            \Log::warning('Maintenance mode notification failed', [
                'app' => $this->app,
                'exception' => $e::class,
            ]);
        }
    }

    protected static function booted(): void
    {
        static::saved(function ($model) {
            static::clearCache($model->app);
            $model->notifyUsers();
        });
        static::deleted(fn ($model) => static::clearCache($model->app));
    }
}
