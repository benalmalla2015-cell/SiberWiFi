<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BankAccount;
use App\Models\ChargingPoint;
use App\Models\User;
use App\Models\WalletLog;
use App\Services\CurrencyService;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class WalletController extends Controller
{
    public function balance(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'success' => true,
            'data' => [
                'balance' => (float) $user->balance,
                'available_balance' => (float) $user->available_balance,
                'frozen_balance' => (float) $user->frozen_balance,
                'advance_balance' => (float) $user->advance_balance,
                'is_eligible_for_advance' => $user->isEligibleForAdvance(),
                'currency' => $user->currency ?? 'YER',
            ],
        ]);
    }

    public function logs(Request $request): JsonResponse
    {
        $logs = WalletLog::where('user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->paginate(30);

        return response()->json([
            'success' => true,
            'data' => $logs->map(fn($l) => [
                'id' => $l->id,
                'type' => $l->type,
                'amount' => (float) $l->amount,
                'balance_before' => (float) $l->balance_before,
                'balance_after' => (float) $l->balance_after,
                'description' => $l->description,
                'reference_type' => $l->reference_type,
                'created_at' => $l->created_at?->toDateTimeString(),
            ])->values(),
            'meta' => [
                'total' => $logs->total(),
                'current_page' => $logs->currentPage(),
                'last_page' => $logs->lastPage(),
            ],
        ]);
    }

    public function searchCustomer(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'phone' => ['required', 'regex:/^[0-9]{9}$/'],
        ], [
            'phone.regex' => 'يجب أن يتكون رقم الجوال من 9 أرقام',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        if (!$this->isChargingPoint($request->user()->id)) {
            return response()->json(['success' => false, 'message' => 'هذه الخدمة متاحة للعملاء المسجلين كنقاط شحن فقط'], 403);
        }

        $customer = User::where('phone', $request->phone)
            ->where('type', 'client')
            ->where('is_active', true)
            ->first(['id', 'name', 'phone']);

        if (!$customer) {
            return response()->json(['success' => false, 'message' => 'لا يوجد عميل مسجل بهذا الرقم'], 404);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $customer->id,
                'name' => $customer->name,
                'phone' => $customer->phone,
            ],
        ]);
    }

    public function bankAccounts(): JsonResponse
    {
        $accounts = BankAccount::where('is_active', true)
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get(['id', 'owner_name', 'bank_name', 'account_number']);

        return response()->json([
            'success' => true,
            'data' => $accounts,
        ]);
    }

    public function topup(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'amount' => 'required|numeric|min:1',
            'bank_account_id' => 'nullable|exists:bank_accounts,id',
            'transfer_receipt_number' => 'nullable|string|max:255',
            'sender_name' => 'nullable|string|max:255',
            'receipt_image' => 'nullable|image|max:5120',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        $amount = (float) $request->amount;
        $bankAccountId = $request->input('bank_account_id');
        $receiptNumber = $request->input('transfer_receipt_number');
        $senderName = $request->input('sender_name');

        $receiptImagePath = null;
        if ($request->hasFile('receipt_image')) {
            $receiptImagePath = $request->file('receipt_image')->store('receipt_images', 'public');
        }

        $bankLabel = '';
        if ($bankAccountId) {
            $account = BankAccount::find($bankAccountId);
            if ($account) {
                $bankLabel = " ({$account->bank_name} / {$account->account_number})";
            }
        }

        WalletLog::create([
            'user_id' => $user->id,
            'type' => 'pending_topup',
            'amount' => $amount,
            'balance_before' => (float) $user->balance,
            'balance_after' => (float) $user->balance,
            'description' => 'طلب شحن رصيد بمبلغ ' . number_format($amount) . ' ريال' . $bankLabel,
            'reference_type' => 'topup_request',
            'bank_account_id' => $bankAccountId,
            'transfer_receipt_number' => $receiptNumber,
            'sender_name' => $senderName,
            'receipt_image' => $receiptImagePath,
        ]);

        try {
            $admins = User::where('type', 'admin')->get();
            foreach ($admins as $admin) {
                $body = 'المستخدم ' . $user->name . ' يطلب شحن رصيد بمبلغ ' . number_format($amount) . ' ريال.';
                if ($receiptNumber) {
                    $body .= ' رقم السند/الحوالة: ' . $receiptNumber;
                }
                if ($senderName) {
                    $body .= ' - اسم المودع: ' . $senderName;
                }
                if ($receiptImagePath) {
                    $body .= ' - تم إرفاق صورة السند';
                }
                app(NotificationService::class)->send(
                    $admin,
                    'طلب شحن رصيد',
                    $body,
                    ['type' => 'topup_request', 'user_id' => $user->id, 'amount' => $amount]
                );
            }
        } catch (\Throwable $e) {
            \Log::warning('Topup notification failed: ' . $e->getMessage());
        }

        $message = 'تم إرسال طلب الشحن، سيتم التواصل معك لإتمامه';
        if ((float) $user->advance_balance > 0) {
            $message .= '. تنبيه: لديك سلفة مستحقة بمبلغ ' . number_format($user->advance_balance) . ' ريال، وسيتم خصمها من مبلغ الشحن أولاً بعد موافقة الإدارة.';
        }

        return response()->json([
            'success' => true,
            'message' => $message,
            'advance_balance' => (float) $user->advance_balance,
        ]);
    }

    public function transfer(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'phone' => ['required', 'regex:/^[0-9]{9}$/'],
            'amount' => 'required|numeric|min:1',
        ], [
            'phone.regex' => 'يجب أن يتكون رقم الجوال من 9 أرقام',
            'amount.min' => 'يجب أن يكون مبلغ الشحن أكبر من صفر',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $sender = $request->user();
        if (!$this->isChargingPoint($sender->id)) {
            return response()->json(['success' => false, 'message' => 'هذه الخدمة متاحة للعملاء المسجلين كنقاط شحن فقط'], 403);
        }

        $recipient = User::where('phone', $request->phone)
            ->where('type', 'client')
            ->where('is_active', true)
            ->first();

        if (!$recipient) {
            return response()->json(['success' => false, 'message' => 'لا يوجد عميل مسجل بهذا الرقم'], 404);
        }
        if ($recipient->id === $sender->id) {
            return response()->json(['success' => false, 'message' => 'لا يمكنك شحن رصيد حسابك نفسه'], 422);
        }

        $amount = round((float) $request->amount, 2);
        try {
            $result = DB::transaction(function () use ($sender, $recipient, $amount) {
                $users = User::whereIn('id', [$sender->id, $recipient->id])
                    ->orderBy('id')
                    ->lockForUpdate()
                    ->get()
                    ->keyBy('id');
                $lockedSender = $users[$sender->id];
                $lockedRecipient = $users[$recipient->id];

                if ((float) $lockedSender->balance < $amount || (float) $lockedSender->available_balance < $amount) {
                    return null;
                }

                $senderBefore = (float) $lockedSender->balance;
                $recipientBefore = (float) $lockedRecipient->balance;
                $receivedAmount = CurrencyService::convert($amount, $lockedSender->region_type, $lockedRecipient->region_type);
                $lockedSender->decrement('balance', $amount);
                $lockedSender->decrement('available_balance', $amount);
                $lockedRecipient->increment('balance', $receivedAmount);
                $lockedRecipient->increment('available_balance', $receivedAmount);

                $senderLog = WalletLog::create([
                    'user_id' => $lockedSender->id,
                    'counterparty_user_id' => $lockedRecipient->id,
                    'type' => 'debit',
                    'amount' => $amount,
                    'balance_before' => $senderBefore,
                    'balance_after' => $senderBefore - $amount,
                    'description' => 'شحن رصيد للعميل ' . $lockedRecipient->name . ' (' . $lockedRecipient->phone . ')',
                    'reference_type' => 'wallet_transfer',
                    'performed_by' => $lockedSender->id,
                ]);

                WalletLog::create([
                    'user_id' => $lockedRecipient->id,
                    'counterparty_user_id' => $lockedSender->id,
                    'type' => 'credit',
                    'amount' => $receivedAmount,
                    'balance_before' => $recipientBefore,
                    'balance_after' => $recipientBefore + $receivedAmount,
                    'description' => 'استلام رصيد من نقطة الشحن ' . $lockedSender->name . ' (' . $lockedSender->phone . ')',
                    'reference_type' => 'wallet_transfer',
                    'reference_id' => $senderLog->id,
                    'performed_by' => $lockedSender->id,
                ]);

                return [
                    'balance' => $senderBefore - $amount,
                    'recipient_name' => $lockedRecipient->name,
                    'recipient_phone' => $lockedRecipient->phone,
                    'amount' => $amount,
                    'received_amount' => $receivedAmount,
                ];
            }, 3);
        } catch (\Throwable $e) {
            \Log::error('Wallet transfer failed', ['sender_id' => $sender->id, 'exception' => $e]);
            return response()->json(['success' => false, 'message' => 'تعذر تنفيذ عملية الشحن، حاول مجدداً'], 500);
        }

        if ($result === null) {
            return response()->json(['success' => false, 'message' => 'رصيدك الحالي غير كافٍ لإتمام العملية'], 422);
        }

        try {
            app(NotificationService::class)->send(
                $recipient,
                'تم استلام رصيد',
                'تمت إضافة ' . number_format($result['received_amount'], 2) . ' إلى رصيدك من نقطة الشحن ' . $sender->name,
                ['type' => 'wallet_transfer', 'sender_id' => $sender->id, 'amount' => $result['received_amount']]
            );
        } catch (\Throwable $e) {
            \Log::warning('Wallet transfer notification failed: ' . $e->getMessage());
        }

        return response()->json(['success' => true, 'message' => 'تم شحن الرصيد بنجاح', 'data' => $result]);
    }

    private function isChargingPoint(int $userId): bool
    {
        return ChargingPoint::where('user_id', $userId)
            ->where('is_active', true)
            ->where('is_approved', true)
            ->whereHas('user', fn($query) => $query->where('is_active', true))
            ->exists();
    }
}
