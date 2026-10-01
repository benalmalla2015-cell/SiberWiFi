<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ChatMessage;
use App\Models\Network;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ChatController extends Controller
{
    public function conversations(Request $request): JsonResponse
    {
        $user = $request->user();
        $networkIds = Network::where('user_id', $user->id)->pluck('id');

        $messages = ChatMessage::with(['network:id,name', 'sender:id,name', 'receiver:id,name'])
            ->whereIn('network_id', $networkIds)
            ->where(fn ($query) => $query
                ->where('sender_id', $user->id)
                ->orWhere('receiver_id', $user->id))
            ->latest()
            ->get();

        $conversations = $messages
            ->groupBy(fn (ChatMessage $message) => $message->network_id . ':' . ($message->sender_id === $user->id ? $message->receiver_id : $message->sender_id))
            ->map(function ($items) use ($user) {
                $latest = $items->first();
                $contact = $latest->sender_id === $user->id ? $latest->receiver : $latest->sender;

                return [
                    'network_id' => $latest->network_id,
                    'network_name' => $latest->network?->name,
                    'contact_id' => $contact?->id,
                    'contact_name' => $contact?->name,
                    'last_message' => $latest->message ?: ($latest->image ? 'صورة' : ''),
                    'last_message_at' => $latest->created_at->toDateTimeString(),
                    'unread_count' => $items->where('receiver_id', $user->id)->where('is_read', false)->count(),
                ];
            })
            ->sortByDesc('last_message_at')
            ->values();

        return response()->json(['success' => true, 'data' => $conversations]);
    }

    public function messages(Request $request, int $networkId): JsonResponse
    {
        $user = $request->user();
        $network = Network::findOrFail($networkId);
        if ($network->user_id !== $user->id && ((int) $network->region_id !== (int) $user->region_id || (int) $network->directorate_id !== (int) $user->directorate_id)) {
            return response()->json(['success' => false, 'message' => 'لا يمكنك مراسلة شبكة خارج مديريتك المختارة'], 403);
        }
        $contactId = $network->user_id === $user->id
            ? (int) $request->query('contact_id')
            : $network->user_id;

        if ($contactId <= 0) {
            return response()->json(['success' => false, 'message' => 'contact_id مطلوب'], 422);
        }

        $messages = ChatMessage::where('network_id', $networkId)
            ->where(function ($query) use ($user, $contactId) {
                $query->where(function ($pair) use ($user, $contactId) {
                    $pair->where('sender_id', $user->id)->where('receiver_id', $contactId);
                })->orWhere(function ($pair) use ($user, $contactId) {
                    $pair->where('sender_id', $contactId)->where('receiver_id', $user->id);
                });
            })
            ->orderBy('created_at')
            ->paginate(50);

        ChatMessage::where('network_id', $networkId)
            ->where('receiver_id', $user->id)
            ->where('is_read', false)
            ->update(['is_read' => true, 'read_at' => now()]);

        return response()->json([
            'success' => true,
            'data' => $messages->map(fn($m) => [
                'id' => $m->id,
                'sender_id' => $m->sender_id,
                'receiver_id' => $m->receiver_id,
                'message' => $m->message,
                'image_url' => $m->image ? asset('storage/' . $m->image) : null,
                'is_read' => (bool) $m->is_read,
                'read_at' => $m->read_at?->toDateTimeString(),
                'created_at' => $m->created_at->toDateTimeString(),
            ])->values(),
            'meta' => [
                'total' => $messages->total(),
                'current_page' => $messages->currentPage(),
                'last_page' => $messages->lastPage(),
            ],
        ]);
    }

    public function send(Request $request, int $networkId): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'message' => 'nullable|string|max:5000',
            'image' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }
        if (!$request->filled('message') && !$request->hasFile('image')) {
            return response()->json(['success' => false, 'message' => 'أدخل رسالة أو اختر صورة للإرسال'], 422);
        }

        $user = $request->user();
        $network = Network::findOrFail($networkId);
        $isOwner = $user->id === $network->user_id;
        if (!$isOwner && ((int) $network->region_id !== (int) $user->region_id || (int) $network->directorate_id !== (int) $user->directorate_id)) {
            return response()->json(['success' => false, 'message' => 'لا يمكنك مراسلة شبكة خارج مديريتك المختارة'], 403);
        }
        $receiverId = $isOwner ? (int) $request->input('receiver_id') : $network->user_id;

        if ($isOwner && ($receiverId <= 0 || $receiverId === $user->id || !\App\Models\User::whereKey($receiverId)->exists())) {
            return response()->json(['success' => false, 'message' => 'المستلم غير صالح'], 422);
        }
        if ($isOwner && !ChatMessage::where('network_id', $network->id)
            ->where(function ($query) use ($user, $receiverId) {
                $query->where(function ($pair) use ($user, $receiverId) {
                    $pair->where('sender_id', $receiverId)->where('receiver_id', $user->id);
                })->orWhere(function ($pair) use ($user, $receiverId) {
                    $pair->where('sender_id', $user->id)->where('receiver_id', $receiverId);
                });
            })
            ->exists()) {
            return response()->json(['success' => false, 'message' => 'لا يمكن إرسال رسالة قبل أن يبدأ العميل المحادثة'], 422);
        }

        $message = ChatMessage::create([
            'network_id' => $network->id,
            'sender_id' => $user->id,
            'receiver_id' => $receiverId,
            'message' => $request->input('message', ''),
            'image' => $request->hasFile('image') ? $request->file('image')->store('chat-images', 'public') : null,
            'is_read' => false,
        ]);

        try {
            $receiver = \App\Models\User::find($receiverId);
            if ($receiver) {
                app(NotificationService::class)->send(
                    $receiver,
                    'رسالة جديدة',
                    'لديك رسالة جديدة من ' . $user->name . ' بخصوص شبكة ' . $network->name,
                    ['type' => 'chat_message', 'network_id' => $network->id, 'message_id' => $message->id]
                );
            }
        } catch (\Throwable $e) {
            \Log::warning('Chat notification failed: ' . $e->getMessage());
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال الرسالة',
            'data' => [
                'id' => $message->id,
                'sender_id' => $message->sender_id,
                'receiver_id' => $message->receiver_id,
                'message' => $message->message,
                'image_url' => $message->image ? asset('storage/' . $message->image) : null,
                'created_at' => $message->created_at->toDateTimeString(),
            ],
        ]);
    }

    public function markRead(Request $request, int $networkId): JsonResponse
    {
        $user = $request->user();

        ChatMessage::where('network_id', $networkId)
            ->where('receiver_id', $user->id)
            ->where('is_read', false)
            ->update(['is_read' => true, 'read_at' => now()]);

        return response()->json(['success' => true, 'message' => 'تم تعيين الرسائل كمقروءة']);
    }
}
