<?php

namespace App\Filament\Resources\SupportTicketResource\Pages;

use App\Filament\Resources\SupportTicketResource;
use Filament\Resources\Pages\EditRecord;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Notifications\DatabaseNotification;
use Illuminate\Support\Str;

class EditSupportTicket extends EditRecord
{
    protected static string $resource = SupportTicketResource::class;

    protected function handleRecordUpdate(Model $record, array $data): Model
    {
        $oldStatus = $record->status;
        $oldReply = $record->reply;
        $hasNewReply = filled($data['reply'] ?? null) && ($data['reply'] ?? null) !== $oldReply;
        if ($hasNewReply) {
            $data['replied_at'] = now();
            $data['replied_by'] = auth()->id();
        }

        $record->update($data);

        if ($hasNewReply || $record->status !== $oldStatus) {
            try {
                $title = $hasNewReply ? 'تم الرد على طلبك' : 'تم تحديث حالة طلبك';
                $body = $hasNewReply
                    ? 'تم الرد على طلب الدعم: ' . $record->subject
                    : 'تم تحديث حالة طلب الدعم: ' . $record->subject;
                $notificationData = [
                    'title' => $title,
                    'body' => $body,
                    'type' => 'support_ticket_reply',
                    'ticket_id' => $record->id,
                    'status' => $record->status,
                ];
                DatabaseNotification::create([
                    'id' => (string) Str::uuid(),
                    'type' => 'App\\Notifications\\SupportTicketNotification',
                    'notifiable_type' => 'App\\Models\\User',
                    'notifiable_id' => $record->user_id,
                    'data' => $notificationData,
                ]);
                app(\App\Services\NotificationService::class)->send(
                    $record->user,
                    $title,
                    $body,
                    $notificationData
                );
            } catch (\Throwable $e) {
                \Log::warning('Support ticket notification failed: ' . $e->getMessage());
            }
        }

        return $record;
    }
}
