<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccAgent;
use App\Models\AccPosPoint;
use App\Models\AccWithdrawal;
use App\Services\AccContext;
use App\Services\AccOrderException;
use App\Services\AccPosAppService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Withdrawal review — the management surface (ACC-07, PLAN §2.2).
 * Owner/admin list every request and decide: approve → paid → or
 * reject (the held profit is refunded atomically).
 */
class AccWithdrawalsController extends Controller
{
    public function __construct(private AccPosAppService $app) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccWithdrawal::where('network_owner_id', $ctx->ownerId)->latest();

        if ($status = $request->query('status')) {
            $query->where('status', $status);
        }
        if ($type = $request->query('requester_type')) {
            $query->where('requester_type', $type);
        }
        if ($id = $request->query('requester_id')) {
            $query->where('requester_id', (int) $id);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(
                fn (AccWithdrawal $w) => $this->serialize($w)
            ),
        ]);
    }

    public function approve(Request $request, int $withdrawal): JsonResponse
    {
        return $this->decide($request, $withdrawal, 'approve', 'تم اعتماد طلب السحب');
    }

    public function paid(Request $request, int $withdrawal): JsonResponse
    {
        return $this->decide($request, $withdrawal, 'paid', 'تم صرف المبلغ وترحيله');
    }

    public function reject(Request $request, int $withdrawal): JsonResponse
    {
        return $this->decide($request, $withdrawal, 'reject', 'تم رفض طلب السحب');
    }

    private function decide(Request $request, int $id, string $action, string $message): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'cash_box_id' => 'nullable|integer',
            'receiver_name' => 'nullable|string|max:190',
            'receipt_no' => 'nullable|string|max:60',
            'review_note' => 'nullable|string|max:190',
            'reason' => 'nullable|string|max:190',
        ]);

        try {
            $w = $this->app->decideWithdrawal($ctx, $id, $action, $data);
        } catch (AccOrderException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], $e->status);
        }

        return response()->json([
            'success' => true,
            'message' => $message,
            'data' => $this->serialize($w),
        ]);
    }

    private function serialize(AccWithdrawal $w): array
    {
        $partyName = $w->requester_type === 'pos'
            ? AccPosPoint::find($w->requester_id)?->name
            : AccAgent::find($w->requester_id)?->display_name;

        return [
            'id' => $w->id,
            'requester_type' => $w->requester_type,
            'requester_id' => $w->requester_id,
            'requester_name' => $partyName,
            'requested_by' => $w->requested_by,
            'amount' => (float) $w->amount,
            'status' => $w->status,
            'receiver_name' => $w->receiver_name,
            'receipt_no' => $w->receipt_no,
            'note' => $w->note,
            'review_note' => $w->review_note,
            'reviewed_by' => $w->reviewed_by,
            'reviewed_at' => $w->reviewed_at?->toISOString(),
            'paid_at' => $w->paid_at?->toISOString(),
            'cash_box_id' => $w->cash_box_id,
            'created_at' => $w->created_at?->toISOString(),
        ];
    }
}
