<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\NetworkRating;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Carbon\Carbon;

class NetworkOwnerRatingController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();

        $ratings = NetworkRating::whereIn('network_id', $networkIds)
            ->with(['user:id,name', 'network:id,name'])
            ->latest()
            ->paginate(20);

        return response()->json([
            'success' => true,
            'data'    => $ratings->map(fn($r) => [
                'id'           => $r->id,
                'network_name' => $r->network?->name,
                'user_name'    => $r->user?->name,
                'rating'       => (float) $r->rating,
                'comment'      => $r->review,
                'owner_reply'  => $r->owner_reply,
                'replied_at'   => $r->replied_at ? Carbon::parse($r->replied_at)->toDateTimeString() : null,
                'created_at'   => $r->created_at->toDateTimeString(),
            ]),
            'meta' => [
                'total'        => $ratings->total(),
                'current_page' => $ratings->currentPage(),
                'last_page'    => $ratings->lastPage(),
            ],
        ]);
    }

    public function reply(Request $request, int $id): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'reply' => 'required|string|max:2000',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $networkIds = $request->user()->networks()->pluck('id')->toArray();
        $rating = NetworkRating::whereIn('network_id', $networkIds)
            ->with(['network:id,name', 'user:id,name'])
            ->findOrFail($id);

        $rating->update([
            'owner_reply' => trim($request->reply),
            'replied_at' => now(),
        ]);

        try {
            app(NotificationService::class)->send(
                $rating->user,
                'رد من صاحب الشبكة',
                'رد صاحب شبكة "' . $rating->network?->name . '" على تقييمك.',
                ['type' => 'rating_reply', 'network_id' => $rating->network_id, 'rating_id' => $rating->id]
            );
        } catch (\Throwable $e) {
            \Log::warning('Rating reply notification failed: ' . $e->getMessage());
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال الرد للعميل',
            'data' => ['owner_reply' => $rating->owner_reply, 'replied_at' => $rating->replied_at ? Carbon::parse($rating->replied_at)->toDateTimeString() : null],
        ]);
    }
}
