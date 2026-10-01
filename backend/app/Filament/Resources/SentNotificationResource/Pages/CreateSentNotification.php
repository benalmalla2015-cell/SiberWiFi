<?php

namespace App\Filament\Resources\SentNotificationResource\Pages;

use App\Filament\Resources\SentNotificationResource;
use App\Models\User;
use App\Services\NotificationService;
use Filament\Resources\Pages\CreateRecord;

class CreateSentNotification extends CreateRecord
{
    protected static string $resource = SentNotificationResource::class;

    protected function mutateFormDataBeforeCreate(array $data): array
    {
        $data['sent_by'] = auth()->id();
        $data['recipients_count'] = 0;
        return $data;
    }

    protected function afterCreate(): void
    {
        $record = $this->record;

        $title   = $record->title;
        $body    = $record->body;
        $target  = $record->target;
        $imageUrl = $record->image_url;
        $payload = $record->payload ?? [];

        $query = User::query()
            ->where('is_active', true)
            ->whereHas('fcmTokens', fn ($q) => $q->where('is_active', true));

        if ($target === 'customer_app') {
            $query->where('type', 'client');
        } elseif ($target === 'network_owner_app') {
            $query->where('type', 'network_owner');
        } elseif ($target === 'all') {
            $query->whereIn('type', ['client', 'network_owner']);
        }

        $count   = 0;
        $service = app(NotificationService::class);

        foreach ($query->cursor() as $user) {
            try {
                $service->send($user, $title, $body, [
                    'type'    => 'general',
                    'target'  => $target,
                    'title'   => $title,
                    'body'    => $body,
                    'image'   => $imageUrl,
                    'payload' => json_encode($payload),
                ], $imageUrl);
            } catch (\Throwable $e) {
                report($e);
            }

            $count++;
        }

        $record->update(['recipients_count' => $count]);

        $this->redirect($this->getResource()::getUrl('index'));
    }
}
