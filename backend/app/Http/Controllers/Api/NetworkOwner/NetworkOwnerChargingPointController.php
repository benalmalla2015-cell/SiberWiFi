<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\ChargingPoint;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class NetworkOwnerChargingPointController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();

        $points = ChargingPoint::whereIn('network_id', $networkIds)
            ->with('network:id,name')
            ->latest()
            ->get()
            ->map(fn($p) => $this->resource($p));

        return response()->json(['success' => true, 'data' => $points]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        $networkIds = $user->networks()->pluck('id')->toArray();

        $validator = Validator::make($request->all(), [
            'network_id'     => 'sometimes|exists:networks,id',
            'customer_phone' => ['nullable', 'regex:/^[0-9]{9}$/'],
            'name'           => 'nullable|string|max:255',
            'phone'          => 'nullable|string|max:20',
            'address'        => 'nullable|string|max:500',
            'working_hours'  => 'nullable|string|max:255',
            'location'       => 'nullable|string|max:500',
            'latitude'       => 'nullable|numeric',
            'longitude'      => 'nullable|numeric',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $networkId = $request->network_id ?? $networkIds[0] ?? null;
        if (!$networkId || !in_array($networkId, $networkIds)) {
            return response()->json(['success' => false, 'message' => 'يرجى تحديد شبكة صالحة'], 403);
        }

        $customer = null;
        if ($request->filled('customer_phone')) {
            $customer = \App\Models\User::where('phone', $request->customer_phone)
                ->where('is_active', true)
                ->where('type', 'client')
                ->first();

            if (!$customer) {
                return response()->json([
                    'success' => false,
                    'message' => 'لا يوجد عميل مسجل بهذا الرقم',
                ], 422);
            }
        }

        $point = ChargingPoint::create([
            'network_id'     => $networkId,
            'user_id'        => $customer?->id,
            'name'           => $customer?->name ?? $request->name ?? 'نقطة شحن',
            'phone'          => $customer?->phone ?? $request->phone,
            'location'       => $request->address ?? $request->location,
            'latitude'       => $request->latitude,
            'longitude'      => $request->longitude,
            'working_hours'  => $request->working_hours,
            'is_active'      => true,
        ]);

        if ($customer) {
            try {
                app(\App\Services\NotificationService::class)->send(
                    $customer,
                    'تم تعيينك كنقطة شحن',
                    "لقد تم إضافتك كنقطة شحن لشبكة {$point->network?->name}.",
                    ['type' => 'charging_point_assigned', 'point_id' => $point->id, 'network_id' => $point->network_id]
                );
            } catch (\Throwable $e) {
                \Log::warning('Charging point assignment notification failed: ' . $e->getMessage());
            }
        }

        return response()->json(['success' => true, 'message' => 'تمت إضافة نقطة الشحن', 'data' => $this->resource($point->load('network:id,name'))], 201);
    }

    public function update(Request $request, int $id): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();
        $point = ChargingPoint::whereIn('network_id', $networkIds)->findOrFail($id);
        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|nullable|string|max:255',
            'phone' => 'sometimes|nullable|string|max:20',
            'location' => 'sometimes|nullable|string|max:500',
            'address' => 'sometimes|nullable|string|max:500',
            'working_hours' => 'sometimes|nullable|string|max:255',
            'latitude' => 'sometimes|nullable|numeric',
            'longitude' => 'sometimes|nullable|numeric',
            'is_active' => 'sometimes|boolean',
        ]);
        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $point->update($request->only([
            'name', 'phone', 'location', 'latitude', 'longitude', 'is_active',
        ]));

        if ($request->has('address')) {
            $point->update(['location' => $request->address]);
        }
        if ($request->has('working_hours')) {
            $point->update(['working_hours' => $request->working_hours]);
        }

        return response()->json(['success' => true, 'message' => 'تم تحديث نقطة الشحن', 'data' => $this->resource($point->fresh()->load('network:id,name'))]);
    }

    public function destroy(Request $request, int $id): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();
        $point = ChargingPoint::whereIn('network_id', $networkIds)->findOrFail($id);
        $point->delete();

        return response()->json(['success' => true, 'message' => 'تم حذف نقطة الشحن']);
    }

    private function resource(ChargingPoint $p): array
    {
        return [
            'id'             => $p->id,
            'name'           => $p->name,
            'phone'          => $p->phone,
            'customer_name'  => $p->user?->name,
            'customer_phone' => $p->user?->phone,
            'customer_id'    => $p->user_id,
            'address'        => $p->location,
            'location'       => $p->location,
            'working_hours'  => $p->working_hours,
            'latitude'       => $p->latitude,
            'longitude'      => $p->longitude,
            'network_id'     => $p->network_id,
            'network_name'   => $p->network?->name,
            'is_active'      => (bool) $p->is_active,
            'is_approved'    => (bool) $p->is_approved,
            'created_at'     => $p->created_at->toDateTimeString(),
        ];
    }
}
