<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $notifications = $request->user()->notifications()->latest()->paginate(30);

        return response()->json([
            'success' => true,
            'data' => $notifications->map(function ($notification): array {
                $data = $this->notificationData($notification->data);

                return [
                    'id' => $notification->id,
                    'title' => $data['title'] ?? 'إشعار',
                    'body' => $data['body'] ?? '',
                    'type' => $data['type'] ?? 'general',
                    'image' => $data['image'] ?? null,
                    'payload' => $data['payload'] ?? null,
                    'read_at' => $notification->read_at?->toDateTimeString(),
                    'created_at' => $notification->created_at->toDateTimeString(),
                ];
            })->values(),
            'unread_count' => $request->user()->unreadNotifications()->count(),
            'meta' => [
                'total' => $notifications->total(),
                'current_page' => $notifications->currentPage(),
                'last_page' => $notifications->lastPage(),
            ],
        ]);
    }

    public function markRead(Request $request, string $id): JsonResponse
    {
        $notification = $request->user()->notifications()->findOrFail($id);
        $notification->markAsRead();

        return response()->json(['success' => true, 'message' => 'تم تعيين الإشعار كمقروء']);
    }

    public function markAllRead(Request $request): JsonResponse
    {
        $request->user()->unreadNotifications->markAsRead();

        return response()->json(['success' => true, 'message' => 'تم تعيين جميع الإشعارات كمقروءة']);
    }

    private function notificationData(mixed $data): array
    {
        if (is_array($data)) {
            return $data;
        }

        if (is_string($data)) {
            $decoded = json_decode($data, true);
            return is_array($decoded) ? $decoded : [];
        }

        return [];
    }
}
