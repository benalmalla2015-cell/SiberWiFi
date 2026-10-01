<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ChargingPoint;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ChargingPointController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $points = ChargingPoint::where('is_active', true)
            ->where('is_approved', true)
            ->with(['network:id,name,region_id,directorate_id', 'network.region:id,name', 'network.directorate:id,name'])
            ->when($request->network_id, fn($q) => $q->where('network_id', $request->network_id))
            ->when($request->region_id, fn($q) => $q->whereHas('network', fn($qq) => $qq->where('region_id', $request->region_id)))
            ->latest()
            ->get()
            ->map(fn($p) => [
                'id'           => $p->id,
                'name'         => $p->name,
                'phone'        => $p->phone,
                'location'     => $p->location,
                'latitude'     => $p->latitude,
                'longitude'    => $p->longitude,
                'network_id'   => $p->network_id,
                'network_name' => $p->network?->name,
                'region'       => $p->network?->region?->name,
                'directorate'  => $p->network?->directorate?->name,
            ]);

        return response()->json(['success' => true, 'data' => $points]);
    }

    public function me(Request $request): JsonResponse
    {
        $phone = $request->user()->phone;
        $point = ChargingPoint::where('phone', $phone)
            ->where('is_active', true)
            ->where('is_approved', true)
            ->with('network:id,name')
            ->first();

        if (!$point) {
            return response()->json(['success' => false, 'message' => 'لا توجد نقطة شحن مرتبطة بهذا الرقم'], 200);
        }

        return response()->json([
            'success' => true,
            'data'    => [
                'id'           => $point->id,
                'name'         => $point->name,
                'phone'        => $point->phone,
                'network_name' => $point->network?->name,
                'is_approved'  => (bool) $point->is_approved,
            ],
        ]);
    }
}
