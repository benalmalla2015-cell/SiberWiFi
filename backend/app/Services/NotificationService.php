<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Notifications\DatabaseNotification;
use Illuminate\Support\Str;
use Kreait\Firebase\Contract\Messaging;
use Kreait\Firebase\Factory;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

class NotificationService
{
    /** @var array<string, Messaging> */
    private array $messagings = [];

    private const CREDENTIAL_PATHS = [
        'customer_app'      => 'firebase/customer-sa.json',
        'network_owner_app' => 'firebase/owner-sa.json',
    ];

    private const CHANNELS = [
        'customer_app'      => 'saiberwifi_general',
        'network_owner_app' => 'saiberwifi_owner_general',
    ];

    private function messagingFor(string $app): ?Messaging
    {
        $path  = self::CREDENTIAL_PATHS[$app] ?? self::CREDENTIAL_PATHS['customer_app'];
        $full  = base_path($path);

        if (!file_exists($full)) {
            \Log::warning("Firebase credentials not found: {$full}");
            return null;
        }

        if (!isset($this->messagings[$app])) {
            try {
                $factory = (new Factory)->withServiceAccount($full);
                $this->messagings[$app] = $factory->createMessaging();
            } catch (\Throwable $e) {
                \Log::warning("Firebase init failed for {$app}: " . $e->getMessage());
                return null;
            }
        }

        return $this->messagings[$app] ?? null;
    }

    public function send(User $user, string $title, string $body, array $data = [], ?string $imageUrl = null): void
    {
        $this->store($user, $title, $body, $data, $imageUrl);

        $appDefault = $user->type === 'network_owner' ? 'network_owner_app' : 'customer_app';

        $tokens = $user->fcmTokens()
            ->where('is_active', true)
            ->get(['token', 'app'])
            ->map(function ($token) use ($appDefault) {
                $token->app = $token->app ?? $appDefault;
                return $token;
            });

        if ($tokens->isEmpty()) {
            return;
        }

        $notification = $imageUrl
            ? Notification::create($title, $body, $imageUrl)
            : Notification::create($title, $body);

        foreach ($tokens->groupBy('app') as $app => $group) {
            $messaging = $this->messagingFor($app);
            if (!$messaging) {
                continue;
            }

            $channel = self::CHANNELS[$app] ?? self::CHANNELS['customer_app'];
            $message = CloudMessage::new()
                ->withNotification($notification)
                ->withAndroidConfig([
                    'priority'     => 'high',
                    'notification' => [
                        'channel_id' => $channel,
                        'visibility' => 'public',
                        'sound'      => 'default',
                    ],
                ])
                ->withData($this->stringifyData($data));

            try {
                $report = $messaging->sendMulticast($message, $group->pluck('token')->toArray());

                if ($report->hasFailures()) {
                    foreach ($report->failures()->getItems() as $failure) {
                        $msg = $failure->error()?->getMessage() ?? '';
                        \Log::warning('FCM token failure: ' . $msg);
                        $this->deactivateDeadToken($failure->target()->value(), $msg);
                    }
                }
            } catch (\Throwable $e) {
                \Log::warning('FCM send failed for ' . $app . ': ' . $e->getMessage());
            }
        }
    }

    public function sendToTokens(array $tokens, string $title, string $body, array $data = [], ?string $imageUrl = null, ?string $app = null): void
    {
        $app = $app ?? 'customer_app';
        if (empty($tokens)) {
            return;
        }

        $messaging = $this->messagingFor($app);
        if (!$messaging) {
            return;
        }

        $notification = $imageUrl
            ? Notification::create($title, $body, $imageUrl)
            : Notification::create($title, $body);

        $channel = self::CHANNELS[$app] ?? self::CHANNELS['customer_app'];
        $message = CloudMessage::new()
            ->withNotification($notification)
            ->withAndroidConfig([
                'priority'     => 'high',
                'notification' => [
                    'channel_id' => $channel,
                    'visibility' => 'public',
                    'sound'      => 'default',
                ],
            ])
            ->withData($this->stringifyData($data));

        try {
            $report = $messaging->sendMulticast($message, $tokens);
            if ($report->hasFailures()) {
                foreach ($report->failures()->getItems() as $failure) {
                    $msg = $failure->error()?->getMessage() ?? '';
                    $this->deactivateDeadToken($failure->target()->value(), $msg);
                }
            }
        } catch (\Throwable $e) {
            \Log::warning('FCM multicast failed for ' . $app . ': ' . $e->getMessage());
        }
    }

    /**
     * Deactivate tokens that can never receive messages again
     * (uninstalled app, stale token, or token issued by another FCM project).
     */
    private function deactivateDeadToken(string $token, string $errorMessage): void
    {
        if (!preg_match('/NotRegistered|SenderId mismatch|registration-token-not-registered|Requested entity was not found/i', $errorMessage)) {
            return;
        }
        try {
            \App\Models\FcmToken::where('token', $token)->update(['is_active' => false]);
        } catch (\Throwable $e) {
            // ignore
        }
    }

    public function sendNewNetworkPendingAlert(): void
    {
        try {
            $admins = User::where('type', 'admin')->get();
            foreach ($admins as $admin) {
                $this->send($admin, 'طلب شبكة جديد', 'تم تسجيل طلب شبكة جديدة في انتظار الموافقة.');
            }
        } catch (\Throwable $e) {
            \Log::warning('Admin alert failed: ' . $e->getMessage());
        }
    }

    public function sendLowStockAlert(User $owner, int $threshold = 10): void
    {
        try {
            $networkIds = $owner->networks()->pluck('id')->toArray();
            if (empty($networkIds)) {
                return;
            }

            $lowStockCategories = \App\Models\CardCategory::whereIn('network_id', $networkIds)
                ->where('is_active', true)
                ->withCount(['cards as available_count' => fn($q) => $q->where('status', 'available')])
                ->having('available_count', '<=', $threshold)
                ->get();

            if ($lowStockCategories->isEmpty()) {
                return;
            }

            $names = $lowStockCategories->pluck('name')->implode('، ');
            $this->send(
                $owner,
                'تنبيه: مخزون الكروت منخفض',
                "الفئات التالية على وشك النفاد ({$threshold} كروت أو أقل): {$names}. يرجى إعادة الشحن.",
                ['type' => 'low_stock', 'category_ids' => $lowStockCategories->pluck('id')->toArray()]
            );
        } catch (\Throwable $e) {
            \Log::warning('Low stock alert failed: ' . $e->getMessage());
        }
    }

    private function store(User $user, string $title, string $body, array $data = [], ?string $imageUrl = null): void
    {
        try {
            DatabaseNotification::create([
                'id'              => (string) Str::uuid(),
                'type'            => 'App\\Notifications\\GeneralNotification',
                'notifiable_type' => 'App\\Models\\User',
                'notifiable_id'   => $user->id,
                'data'            => array_merge($data, [
                    'title' => $title,
                    'body'  => $body,
                    'type'  => $data['type'] ?? 'general',
                    'image' => $imageUrl ?? ($data['image'] ?? null),
                ]),
                'read_at'         => null,
                'created_at'      => now(),
                'updated_at'      => now(),
            ]);
        } catch (\Throwable $e) {
            \Log::warning('Notification store failed: ' . $e->getMessage());
        }
    }

    private function stringifyData(array $data): array
    {
        return collect($data)->mapWithKeys(function ($value, $key) {
            return [$key => is_scalar($value) ? (string) $value : json_encode($value)];
        })->toArray();
    }
}
