<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MaintenanceMode;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MaintenanceModeController extends Controller
{
    public function status(Request $request, string $app): JsonResponse
    {
        $validApps = ['customer_app', 'network_owner_app'];
        if (!in_array($app, $validApps, true)) {
            return response()->json(['success' => false, 'message' => 'تطبيق غير صالح'], 422);
        }

        $config = MaintenanceMode::getFor($app);

        if (!$config || !$config->is_active) {
            return response()->json([
                'success' => true,
                'data'    => [
                    'is_active'   => false,
                    'title'       => null,
                    'description' => null,
                    'image'       => null,
                ],
            ]);
        }

        return response()->json([
            'success' => true,
            'data'    => [
                'is_active'   => true,
                'title'       => $config->title,
                'description' => $config->description,
                'image'       => $config->image_url,
            ],
        ]);
    }
}
