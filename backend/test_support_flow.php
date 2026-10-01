<?php

use App\Models\SupportTicket;
use App\Models\User;
use App\Services\NotificationService;
use Illuminate\Notifications\DatabaseNotification;
use Illuminate\Support\Str;

require __DIR__ . '/vendor/autoload.php';
$app = require_once __DIR__ . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$ticket = SupportTicket::where('user_id', 28)->latest()->firstOrFail();
$admin = User::where('type', 'admin')->first();
$ticket->update([
    'status' => 'closed',
    'reply' => 'تم حل المشكلة، شكراً لتواصلك.',
    'replied_by' => $admin?->id,
    'replied_at' => now(),
]);

$notificationData = [
    'title' => 'تم الرد على طلبك',
    'body' => 'تم الرد على طلب الدعم: ' . $ticket->subject,
    'type' => 'support_ticket_reply',
    'ticket_id' => $ticket->id,
    'status' => $ticket->status,
];

DatabaseNotification::create([
    'id' => (string) Str::uuid(),
    'type' => 'App\\Notifications\\SupportTicketNotification',
    'notifiable_type' => 'App\\Models\\User',
    'notifiable_id' => $ticket->user_id,
    'data' => $notificationData,
]);

app(NotificationService::class)->send(
    $ticket->user,
    $notificationData['title'],
    $notificationData['body'],
    $notificationData
);

echo json_encode([
    'ticket_id' => $ticket->id,
    'status' => $ticket->status,
    'reply' => $ticket->reply,
    'user_id' => $ticket->user_id,
], JSON_UNESCAPED_UNICODE) . PHP_EOL;
