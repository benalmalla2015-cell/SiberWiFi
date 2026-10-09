<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\FcmToken;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'name'                  => ['required', 'string', 'max:255', function ($attribute, $value, $fail) {
                if (count(preg_split('/\s+/u', trim($value), -1, PREG_SPLIT_NO_EMPTY)) < 4) {
                    $fail('يجب إدخال الاسم الرباعي على الأقل');
                }
            }],
            'phone'                 => ['required', 'regex:/^[0-9]{9}$/', 'unique:users,phone'],
            'password'              => 'required|string|min:6|confirmed',
            'region_id'             => 'required|exists:regions,id',
            'directorate_id'        => 'required|exists:directorates,id',
            'sub_directorate_id'    => 'required|exists:sub_directorates,id',
            'device_id'             => 'nullable|string|max:191',
            'password_confirmation' => 'required',
        ], [
            'phone.regex' => 'يجب أن يتكون رقم الجوال من 9 أرقام',
            'device_id.required' => 'معرّف الجهاز مطلوب',
            'device_id.unique'   => 'هذا الجهاز مرتبط بحساب آخر',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $region = \App\Models\Region::findOrFail($request->region_id);
        $directorate = \App\Models\Directorate::findOrFail($request->directorate_id);
        if ((int) $directorate->region_id !== (int) $region->id) {
            return response()->json(['success' => false, 'message' => 'المحافظة المختارة لا تتبع المنطقة المحددة'], 422);
        }
        $subDirectorate = \App\Models\SubDirectorate::findOrFail($request->sub_directorate_id);
        if ((int) $subDirectorate->directorate_id !== (int) $directorate->id) {
            return response()->json(['success' => false, 'message' => 'المديرية المختارة لا تتبع المحافظة المحددة'], 422);
        }

        $referredBy = null;
        $referralCode = trim((string) ($request->input('referral_code') ?? $request->input('referralCode') ?? $request->input('referral')));
        if ($referralCode !== '') {
            if (preg_match('/[?&]ref=([^&\s]+)/i', $referralCode, $matches)) {
                $referralCode = urldecode($matches[1]);
            }
            $referrer = User::where('referral_code', strtoupper(trim($referralCode)))->first();
            if (!$referrer) {
                return response()->json(['success' => false, 'message' => 'كود الإحالة غير صحيح'], 422);
            }
            $referredBy = $referrer->id;
        }

        $user = User::create([
            'name'               => $request->name,
            'phone'              => $request->phone,
            'password'           => $request->password,
            'type'               => 'client',
            'region_type'        => $region->type ?? 'north',
            'region_id'          => $region->id,
            'directorate_id'     => $directorate->id,
            'sub_directorate_id' => $subDirectorate->id,
            'account_number'     => $this->generateAccountNumber(),
            'device_id'          => null,
            'referral_code'      => $this->generateReferralCode(),
            'referred_by'        => $referredBy,
            'is_active'          => true,
        ]);

        if ($referredBy) {
            $this->creditReferralCommission($referredBy, $user);
        }

        $token = $user->createToken('mobile_app')->plainTextToken;

        if ($request->fcm_token) {
            $this->saveFcmToken($user->id, $request->fcm_token, $request);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء الحساب بنجاح',
            'token'   => $token,
            'user'    => $this->userResource($user),
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'phone'     => ['required', 'regex:/^[0-9]{9}$/'],
            'device_id' => 'nullable|string|max:191',
            'password' => 'required|string',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = User::where('phone', $request->phone)->first();

        if (!$user || !Hash::check($request->password, $user->password)) {
            return response()->json(['success' => false, 'message' => 'رقم الهاتف أو كلمة المرور غير صحيحة'], 401);
        }

        if ($request->header('X-App-Type') === 'network_owner_app'
            && $user->type !== 'network_owner'
            && !$user->networks()->exists()
            && !$user->networkOwnerProfile()->exists()) {
            return response()->json(['success' => false, 'message' => 'هذا الحساب ليس حساب صاحب شبكة'], 403);
        }

        if (!$user->is_active) {
            return response()->json(['success' => false, 'message' => 'تم إيقاف الحساب من قبل إدارة التطبيق يرجى مراجعة الدعم الفني'], 403);
        }

        $user->tokens()->delete();
        $token = $user->createToken('mobile_app')->plainTextToken;

        if ($request->fcm_token) {
            $this->saveFcmToken($user->id, $request->fcm_token, $request);
        }

        $user->load(['networkOwnerProfile', 'networks']);

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل الدخول بنجاح',
            'token'   => $token,
            'user'    => $this->userResource($user),
        ]);
    }

    public function registerNetworkOwner(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'name'                  => ['required', 'string', 'max:255', function ($attribute, $value, $fail) {
                if (count(preg_split('/\s+/u', trim($value), -1, PREG_SPLIT_NO_EMPTY)) < 4) {
                    $fail('يجب إدخال الاسم الرباعي على الأقل');
                }
            }],
            'phone'                 => ['required', 'regex:/^[0-9]{9}$/', 'unique:users,phone'],
            'password'              => 'required|string|min:6|confirmed',
            'device_id'             => 'nullable|string|max:191',
            'password_confirmation' => 'required',
            'network_name'            => 'required|string|max:255',
            'region_id'               => 'required|exists:regions,id',
            'directorate_id'          => 'required|exists:directorates,id',
            'sub_directorate_id'      => 'required|exists:sub_directorates,id',
            'description'             => 'nullable|string|max:2000',
            'url'                     => 'nullable|url|max:255',
            'cover_image'             => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
            'background_image'        => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
        ], [
            'phone.regex' => 'يجب أن يتكون رقم الهاتف من 9 أرقام',
            'device_id.required' => 'معرّف الجهاز مطلوب',
            'device_id.unique' => 'هذا الجهاز مرتبط بحساب آخر',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $region = \App\Models\Region::find($request->region_id);
        $directorate = \App\Models\Directorate::findOrFail($request->directorate_id);
        if ((int) $directorate->region_id !== (int) $request->region_id) {
            return response()->json(['success' => false, 'message' => 'المحافظة المختارة لا تتبع المنطقة المحددة'], 422);
        }
        $subDirectorate = \App\Models\SubDirectorate::findOrFail($request->sub_directorate_id);
        if ((int) $subDirectorate->directorate_id !== (int) $directorate->id) {
            return response()->json(['success' => false, 'message' => 'المديرية المختارة لا تتبع المحافظة المحددة'], 422);
        }

        $user = User::create([
            'name'               => $request->name,
            'phone'              => $request->phone,
            'password'           => $request->password,
            'type'               => 'network_owner',
            'region_type'        => $region?->type === 'south' ? 'south' : 'north',
            'region_id'          => $request->region_id,
            'directorate_id'     => $request->directorate_id,
            'sub_directorate_id' => $subDirectorate->id,
            'account_number'     => $this->generateAccountNumber(),
            'device_id'          => null,
            'referral_code'      => $this->generateReferralCode(),
            'is_active'          => true,
        ]);

        \App\Models\NetworkOwner::create([
            'user_id'     => $user->id,
            'business_name' => $request->network_name,
            'is_approved' => false,
        ]);

        $networkData = [
            'user_id'            => $user->id,
            'region_id'          => $request->region_id,
            'directorate_id'     => $request->directorate_id,
            'sub_directorate_id' => $subDirectorate->id,
            'name'           => $request->network_name,
            'description'    => $request->description,
            'url'            => $request->url,
            'slug'           => Str::slug($request->network_name) . '-' . uniqid(),
            'status'         => 'pending',
        ];

        foreach (['cover_image', 'background_image'] as $img) {
            if ($request->hasFile($img)) {
                $networkData[$img] = $request->file($img)->store("networks/{$img}s", 'public');
            }
        }

        $network = \App\Models\Network::create($networkData);

        $token = $user->createToken('mobile_app')->plainTextToken;

        if ($request->fcm_token) {
            $this->saveFcmToken($user->id, $request->fcm_token, $request);
        }

        try {
            app(\App\Services\NotificationService::class)->sendNewNetworkPendingAlert();
        } catch (\Throwable $e) {
            \Log::warning('Failed to send new network pending alert: ' . $e->getMessage());
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء الحساب وإرسال طلب الشبكة للمراجعة. سيتم إعلامك بعد الموافقة.',
            'token'   => $token,
            'user'    => $this->userResource($user->load(['networkOwnerProfile', 'networks'])),
            'network' => $this->pendingNetworkResource($network),
        ], 201);
    }

    public function myNetwork(Request $request): JsonResponse
    {
        $network = $request->user()->networks()->with(['region', 'directorate'])->first();

        if (!$network) {
            return response()->json(['success' => false, 'message' => 'لا توجد شبكة مسجلة لهذا الحساب'], 404);
        }

        return response()->json([
            'success' => true,
            'data'    => $this->pendingNetworkResource($network),
        ]);
    }

    public function updateMyNetwork(Request $request): JsonResponse
    {
        $network = $request->user()->networks()->first();

        if (!$network) {
            return response()->json(['success' => false, 'message' => 'لا توجد شبكة مسجلة لهذا الحساب'], 404);
        }

        $validator = Validator::make($request->all(), [
            'name'               => 'sometimes|string|max:255',
            'description'        => 'nullable|string|max:2000',
            'url'                => 'nullable|url|max:255',
            'region_id'          => 'sometimes|required|exists:regions,id',
            'directorate_id'     => 'sometimes|required|exists:directorates,id',
            'sub_directorate_id' => 'sometimes|required|exists:sub_directorates,id',
            'cover_image'        => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
            'background_image'   => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $data = $request->only(['name', 'description', 'url', 'region_id', 'directorate_id', 'sub_directorate_id']);

        foreach (['cover_image', 'background_image'] as $img) {
            if ($request->hasFile($img)) {
                $data[$img] = $request->file($img)->store("networks/{$img}s", 'public');
            }
        }

        $network->update($data);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث بيانات الشبكة',
            'data'    => $this->pendingNetworkResource($network->fresh(['region', 'directorate'])),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        FcmToken::where('user_id', $request->user()->id)->update(['is_active' => false]);
        $request->user()->tokens()->delete();
        return response()->json(['success' => true, 'message' => 'تم تسجيل الخروج']);
    }

    /**
     * Permanently delete the authenticated user's account.
     * Uses soft delete so financial transaction records remain intact,
     * while personal identifiers are anonymized and all sessions are revoked.
     */
    public function deleteAccount(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'password' => 'required|string',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();

        if (!Hash::check($request->password, $user->password)) {
            return response()->json(['success' => false, 'message' => 'كلمة المرور الحالية غير صحيحة'], 422);
        }

        // Revoke all active sessions and push tokens
        $user->tokens()->delete();
        FcmToken::where('user_id', $user->id)->delete();

        // Anonymize personal data before soft deleting. The phone column is
        // varchar(20)+unique, so the placeholder is kept short and unique.
        $user->name    = 'مستخدم محذوف';
        $user->phone   = 'del' . $user->id . 'x' . mt_rand(1000, 9999);
        $user->email   = null;
        $user->avatar  = null;
        $user->device_id = null;
        $user->is_active = false;
        $user->save();

        // Soft delete so related records (transactions, networks, etc.) keep FK integrity
        $user->delete();

        return response()->json(['success' => true, 'message' => 'تم حذف الحساب بنجاح']);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json([
            'success' => true,
            'user'    => $this->userResource($request->user()->load(['networkOwnerProfile', 'networks'])),
        ]);
    }

    public function updateFcmToken(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), ['fcm_token' => 'required|string']);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }
        $this->saveFcmToken($request->user()->id, $request->fcm_token, $request);
        return response()->json(['success' => true, 'message' => 'تم تحديث رمز الإشعارات']);
    }

    public function payoutDetails(Request $request): JsonResponse
    {
        $profile = $request->user()->networkOwnerProfile;

        if (!$profile) {
            return response()->json([
                'success' => true,
                'data' => [
                    'full_name' => null,
                    'provider' => null,
                    'account_number' => null,
                ],
            ]);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'full_name' => $profile->payout_full_name,
                'provider' => $profile->payout_provider,
                'account_number' => $profile->payout_account_number,
            ],
        ]);
    }

    public function updatePayoutDetails(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'full_name' => ['required', 'string', 'max:255', function ($attribute, $value, $fail) {
                $nameCount = count(preg_split('/\s+/u', trim($value), -1, PREG_SPLIT_NO_EMPTY));
                if ($nameCount < 4) {
                    $fail('يجب إدخال الاسم الرباعي على الأقل (4 أسماء)');
                }
            }],
            'provider' => 'nullable|string|max:255',
            'account_number' => 'nullable|string|max:255',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $profile = \App\Models\NetworkOwner::firstOrCreate(['user_id' => $request->user()->id]);
        $profile->update([
            'payout_full_name' => $request->full_name,
            'payout_provider' => $request->provider,
            'payout_account_number' => $request->account_number,
        ]);

        return response()->json(['success' => true, 'message' => 'تم حفظ بيانات المدفوعات والسحب']);
    }

    private function saveFcmToken(int $userId, string $token, Request $request): void
    {
        $user = User::find($userId);
        $appFromHeader = $request->header('X-App-Type');
        $appDefault = $user?->type === 'network_owner' ? 'network_owner_app' : 'customer_app';

        FcmToken::updateOrCreate(
            ['token' => $token],
            [
                'user_id'      => $userId,
                'device_model' => $request->header('X-Device-Model'),
                'app'          => $appFromHeader ?? $appDefault,
                'app_version'  => $request->header('X-App-Version'),
                'is_active'    => true,
                'last_used_at' => now(),
            ]
        );
    }

    private function generateAccountNumber(): string
    {
        do {
            $number = 'SW' . str_pad(random_int(0, 99999999), 8, '0', STR_PAD_LEFT);
        } while (User::where('account_number', $number)->exists());
        return $number;
    }

    private function generateReferralCode(): string
    {
        do {
            $code = strtoupper(Str::random(8));
        } while (User::where('referral_code', $code)->exists());
        return $code;
    }

    private function userResource(User $user): array
    {
        $networkOwner = $user->networkOwnerProfile;
        $network      = $user->networks->first();

        return [
            'id'                       => $user->id,
            'name'                     => $user->name,
            'phone'                    => $user->phone,
            'email'                    => $user->email,
            'type'                     => $user->type,
            'region_type'              => $user->region_type,
            'region_id'                => $user->region_id,
            'directorate_id'           => $user->directorate_id,
            'sub_directorate_id'       => $user->sub_directorate_id,
            'region_name'              => $user->region?->name,
            'directorate_name'         => $user->directorate?->name,
            'sub_directorate_name'     => $user->subDirectorate?->name,
            'currency_label'           => \App\Services\CurrencyService::currencyLabel($user->region_type),
            'account_number'           => $user->account_number,
            'balance'                  => (float) $user->balance,
            'available_balance'        => (float) $user->available_balance,
            'frozen_balance'           => (float) $user->frozen_balance,
            'total_earnings'           => (float) $user->total_earnings,
            'referral_code'            => $user->referral_code,
            'avatar_url'               => $user->avatar_url,
            'is_active'                => (bool) $user->is_active,
            'is_verified'              => (bool) $user->is_verified,
            'currency'                 => $user->currency,
            'is_network_owner'         => (bool) $networkOwner,
            'network_owner_approved'   => (bool) ($networkOwner?->is_approved ?? false) || $user->networks->contains(fn ($network) => $network->status === 'active'),
            'network_status'           => $network?->status,
            'network_id'               => $network?->id,
            'network_code'             => $network?->code,
        ];
    }

    private function pendingNetworkResource(\App\Models\Network $network): array
    {
        return [
            'id'                   => $network->id,
            'code'                 => $network->code,
            'name'                 => $network->name,
            'slug'                 => $network->slug,
            'cover_image_url'      => $network->cover_image_url,
            'background_image_url' => $network->background_image_url,
            'region'               => $network->region?->name,
            'region_id'            => $network->region_id,
            'region_type'          => $network->region?->type,
            'directorate'          => $network->directorate?->name,
            'directorate_id'       => $network->directorate_id,
            'sub_directorate'      => $network->subDirectorate?->name,
            'sub_directorate_id'   => $network->sub_directorate_id,
            'description'          => $network->description,
            'phone'                => $network->phone,
            'url'                  => $network->url,
            'status'               => $network->status,
            'rejection_reason'     => $network->rejection_reason,
            'average_rating'       => (float) $network->average_rating,
            'sales_count'          => $network->sales_count,
            'created_at'           => $network->created_at->toDateTimeString(),
        ];
    }
    private function creditReferralCommission(int $referrerId, User $referred): void
    {
        $referrer = User::find($referrerId);
        if (!$referrer) {
            return;
        }

        $setting = \App\Models\CommissionSetting::where('type', 'referral')->where('region_type', $referrer->region_type)->first();
        $amount = $setting ? (float) $setting->fixed_amount : 0;

        \DB::transaction(function () use ($referrer, $referred, $amount) {
            if ($amount > 0) {
                $balanceBefore = (float) $referrer->balance;

                $referrer->increment('balance', $amount);
                $referrer->increment('available_balance', $amount);

                \App\Models\WalletLog::create([
                    'user_id' => $referrer->id,
                    'type' => 'referral_commission',
                    'amount' => $amount,
                    'balance_before' => $balanceBefore,
                    'balance_after' => (float) $referrer->balance,
                    'description' => 'عمولة إحالة ' . $referred->name . ' (' . $referred->phone . ')',
                    'reference_type' => 'referral',
                    'reference_id' => $referred->id,
                ]);
            }

            \App\Models\Referral::create([
                'referrer_id' => $referrer->id,
                'referred_id' => $referred->id,
                'commission_amount' => $amount,
                'is_paid' => $amount > 0,
                'paid_at' => $amount > 0 ? now() : null,
            ]);
        });
    }
}