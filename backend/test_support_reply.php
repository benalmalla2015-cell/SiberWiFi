<?php

use App\Models\SupportTicket;
use App\Services\NotificationService;

require __DIR__ . '/vendor/autoload.php';
$app = require_once __DIR__ . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$ticket = SupportTicket::where('user_id', 28)->latest()->firstOrFail();
$ticket->update([
    'status' => 'in_progress',
    'reply' => 'تم استلام طلبك التجريبي وجارٍ التحقق منه.',
    'replied_by' => App\Models\User::where('type', 'admin')->value('id'),
    'replied_at' => now(),
]);
app(NotificationService::class)->send(
    $ticket->user,
    'تم الرد على طلبك',
    'تم الرد على طلب الدعم: ' . $ticket->subject,
    ['type' => 'support_ticket_reply', 'ticket_id' => $ticket->id, 'status' => $ticket->status]
);
echo json_encode(['id' => $ticket->id, 'status' => $ticket->status, 'reply' => $ticket->reply], JSON_UNESCAPED_UNICODE) . PHP_EOL;
