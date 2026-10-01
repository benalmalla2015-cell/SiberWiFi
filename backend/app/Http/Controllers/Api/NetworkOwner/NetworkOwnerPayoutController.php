<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\PayoutRequest;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class NetworkOwnerPayoutController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $payouts = PayoutRequest::where('user_id', $request->user()->id)
            ->latest()
            ->paginate(20);

        return response()->json([
            'success' => true,
            'data'    => $payouts->map(fn($p) => $this->resource($p)),
            'meta'    => [
                'total'        => $payouts->total(),
                'current_page' => $payouts->currentPage(),
                'last_page'    => $payouts->lastPage(),
            ],
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'amount' => 'required|numeric|min:100',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user   = $request->user();
        $amount = (float) $request->amount;

        $hasPending = PayoutRequest::where('user_id', $user->id)
            ->whereIn('status', ['pending', 'approved'])
            ->exists();

        if ($hasPending) {
            return response()->json([
                'success' => false,
                'message' => 'لديك طلب سحب قيد المراجعة، يرجى الانتظار حتى يتم معالجته',
            ], 422);
        }

        try {
            $payout = DB::transaction(function () use ($user, $amount) {
                $lockedUser = User::lockForUpdate()->findOrFail($user->id);

                if ((float) $lockedUser->available_balance < $amount) {
                    throw new \RuntimeException('رصيدك المتاح غير كافٍ. الرصيد المتاح: ' . number_format($lockedUser->available_balance, 0) . ' ريال');
                }

                $lockedUser->decrement('available_balance', $amount);
                $lockedUser->increment('frozen_balance', $amount);

                return PayoutRequest::create([
                    'request_number' => 'PAYOUT-' . now()->format('YmdHis') . '-' . strtoupper(Str::random(6)),
                    'user_id' => $user->id,
                    'amount'  => $amount,
                    'requested_amount' => $amount,
                    'remaining_amount' => $amount,
                    'status'  => 'pending',
                    'is_frozen' => true,
                ]);
            });
        } catch (\RuntimeException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال طلب السحب بنجاح. سيتم مراجعته من قِبل الإدارة.',
            'data'    => $this->resource($payout),
        ], 201);
    }

    public function confirmReceipt(Request $request, int $id): JsonResponse
    {
        $payout = PayoutRequest::where('user_id', $request->user()->id)->findOrFail($id);

        if ($payout->status !== 'paid_unconfirmed') {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن تأكيد الاستلام لهذا الطلب. الحالة الحالية: ' . $payout->status,
            ], 422);
        }

        $payout->update([
            'status'                => 'received',
            'received_confirmed_at' => now(),
        ]);

        return response()->json([
            'success' => true,
            'message' => 'تم تأكيد استلام المبلغ بنجاح. شكراً لك.',
            'data'    => $this->resource($payout->fresh()),
        ]);
    }

    private function resource(PayoutRequest $p): array
    {
        return [
            'id'                     => $p->id,
            'request_number'         => $p->request_number,
            'amount'                 => (float) $p->amount,
            'requested_amount'       => (float) ($p->requested_amount ?? $p->amount),
            'remaining_amount'       => (float) ($p->remaining_amount ?? 0),
            'paid_amount'            => $p->paid_amount ? (float) $p->paid_amount : null,
            'service_name'           => $p->service_name,
            'transaction_number'     => $p->transaction_number,
            'status'                 => $p->status,
            'status_label'           => match($p->status) {
                'pending'          => 'قيد المراجعة',
                'approved'         => 'تمت الموافقة',
                'paid_unconfirmed' => 'تم الصرف - بانتظار تأكيدك',
                'received'         => 'مكتمل',
                'rejected'         => 'مرفوض',
                default            => $p->status,
            },
            'admin_notes'            => $p->admin_notes,
            'rejection_reason'       => $p->rejection_reason,
            'paid_at'                => $p->paid_at?->toDateTimeString(),
            'received_confirmed_at'  => $p->received_confirmed_at?->toDateTimeString(),
            'created_at'             => $p->created_at->toDateTimeString(),
            'requires_confirmation'  => $p->status === 'paid_unconfirmed',
        ];
    }
}
