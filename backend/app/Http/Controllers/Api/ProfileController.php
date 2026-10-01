<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use App\Models\Referral;

class ProfileController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'name' => ['sometimes', 'required', 'string', 'max:255', function ($attribute, $value, $fail) {
                if (count(preg_split('/\s+/u', trim($value), -1, PREG_SPLIT_NO_EMPTY)) < 4) {
                    $fail('يجب إدخال الاسم الرباعي على الأقل');
                }
            }],
            'email' => 'nullable|email|max:255|unique:users,email,' . $request->user()->id,
            'directorate_id' => 'sometimes|required|exists:directorates,id',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        if ($request->has('directorate_id')) {
            $directorate = \App\Models\Directorate::whereKey($request->integer('directorate_id'))
                ->where('region_id', $user->region_id)
                ->where('is_active', true)
                ->first();
            if (!$directorate) {
                return response()->json(['success' => false, 'message' => 'يمكنك اختيار مديرية ضمن منطقتك فقط'], 422);
            }
            $user->directorate_id = $directorate->id;
        }
        $user->fill($request->only(['name', 'email']));
        $user->save();

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث بيانات الحساب',
            'data' => [
                'name' => $user->name,
                'email' => $user->email,
                'phone' => $user->phone,
                'region_id' => $user->region_id,
                'directorate_id' => $user->directorate_id,
                'directorate_name' => $user->directorate?->name,
            ],
        ]);
    }

    public function changePassword(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'current_password' => 'required|string',
            'password' => 'required|string|min:6|confirmed',
            'password_confirmation' => 'required|string',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        if (!Hash::check($request->current_password, $user->password)) {
            return response()->json(['success' => false, 'message' => 'كلمة المرور الحالية غير صحيحة'], 422);
        }

        $user->password = $request->password;
        $user->save();

        return response()->json(['success' => true, 'message' => 'تم تغيير كلمة المرور بنجاح']);
    }

    public function updateAvatar(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'avatar' => 'required|image|mimes:jpg,jpeg,png,webp|max:4096',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        $path = $request->file('avatar')->store('avatars', 'public');
        $user->update(['avatar' => $path]);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الصورة الشخصية',
            'data' => ['avatar_url' => $user->avatar_url],
        ]);
    }

    public function referralInfo(Request $request): JsonResponse
    {
        $user = $request->user();
        // إجمالي الأرباح يشمل فقط عمولات التسجيل عبر كود الدعوة (بدون عمولات شراء الكروت)
        $earnings = Referral::where('referrer_id', $user->id)
            ->whereNull('transaction_id')
            ->sum('commission_amount');
        // عدد الأشخاص المدعوين فقط من خلال تسجيلهم بكود الدعوة (بدون عمليات شراء)
        $referralsCount = Referral::where('referrer_id', $user->id)
            ->whereNull('transaction_id')
            ->distinct('referred_id')
            ->count('referred_id');

        return response()->json(['success' => true, 'data' => [
            'referral_code' => $user->referral_code,
            'total_earnings' => (float) $earnings,
            'referrals_count' => $referralsCount,
        ]]);
    }
}
