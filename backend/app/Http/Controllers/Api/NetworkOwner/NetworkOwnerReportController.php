<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\Report;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class NetworkOwnerReportController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();

        $reports = Report::whereIn('network_id', $networkIds)
            ->with(['user:id,name,phone'])
            ->latest()
            ->paginate(20);

        return response()->json([
            'success' => true,
            'data'    => $reports->map(fn($r) => [
                'id'          => $r->id,
                'user_name'   => $r->user?->name,
                'user_phone'  => $r->user?->phone,
                'type'        => $r->type,
                'subject'     => $r->subject,
                'message'     => $r->message,
                'description' => $r->message,
                'status'      => $r->status,
                'admin_reply' => $r->admin_reply,
                'created_at'  => $r->created_at->toDateTimeString(),
            ])->values(),
            'meta' => [
                'total'        => $reports->total(),
                'current_page' => $reports->currentPage(),
                'last_page'    => $reports->lastPage(),
            ],
        ]);
    }

    public function reply(Request $request, int $id): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();
        $report = Report::whereIn('network_id', $networkIds)->findOrFail($id);

        $validator = Validator::make($request->all(), [
            'reply' => 'required|string|max:1000',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $report->update([
            'admin_reply' => $request->reply,
            'status'      => 'resolved',
            'replied_at'  => now(),
            'replied_by'  => $request->user()->id,
        ]);

        try {
            app(NotificationService::class)->send(
                $report->user,
                'رد على بلاغك',
                'تم الرد على بلاغك بخصوص شبكة ' . $report->network?->name . ': ' . $request->reply,
                ['type' => 'report_reply', 'report_id' => $report->id]
            );
        } catch (\Throwable $e) {
            \Log::warning('Report reply notification failed: ' . $e->getMessage());
        }

        return response()->json(['success' => true, 'message' => 'تم إرسال الرد بنجاح']);
    }
}
