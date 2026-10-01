<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SupportTicket;
use App\Models\User;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class SupportTicketController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $tickets = SupportTicket::where('user_id', $request->user()->id)
            ->latest()
            ->paginate(30);

        return response()->json([
            'success' => true,
            'data' => $tickets->map(fn (SupportTicket $ticket) => $this->resource($ticket))->values(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'subject' => 'required|string|max:255',
            'message' => 'required|string|max:5000',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $ticket = SupportTicket::create([
            'user_id' => $request->user()->id,
            'subject' => $request->subject,
            'message' => $request->message,
            'status' => 'open',
        ]);

        try {
            foreach (User::where('type', 'admin')->get() as $admin) {
                app(NotificationService::class)->send(
                    $admin,
                    'طلب دعم جديد',
                    'أرسل ' . $request->user()->name . ' طلب دعم: ' . $ticket->subject,
                    ['type' => 'support_ticket', 'ticket_id' => $ticket->id]
                );
            }
        } catch (\Throwable $e) {
            \Log::warning('Support ticket notification failed: ' . $e->getMessage());
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال طلب الدعم بنجاح',
            'data' => $this->resource($ticket),
        ], 201);
    }

    private function resource(SupportTicket $ticket): array
    {
        return [
            'id' => $ticket->id,
            'subject' => $ticket->subject,
            'message' => $ticket->message,
            'status' => $ticket->status,
            'reply' => $ticket->reply,
            'created_at' => $ticket->created_at->toDateTimeString(),
            'replied_at' => $ticket->replied_at?->toDateTimeString(),
        ];
    }
}
