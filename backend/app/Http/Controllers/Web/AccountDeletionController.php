<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\AccountDeletionRequest;
use Illuminate\Http\Request;

class AccountDeletionController extends Controller
{
    public function show()
    {
        return view('legal.delete-account');
    }

    public function submit(Request $request)
    {
        $validated = $request->validate([
            'phone'    => 'required|string|max:20',
            'app_type' => 'required|in:customer_app,network_owner_app',
            'notes'    => 'nullable|string|max:2000',
        ], [
            'phone.required'    => 'يرجى إدخال رقم الهاتف المرتبط بالحساب.',
            'app_type.required' => 'يرجى اختيار التطبيق.',
            'app_type.in'       => 'التطبيق المختار غير صالح.',
        ]);

        AccountDeletionRequest::create($validated + ['status' => 'pending']);

        return redirect()->route('delete-account')->with('success', true);
    }
}
