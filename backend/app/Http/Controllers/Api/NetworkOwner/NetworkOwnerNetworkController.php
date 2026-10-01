<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\Network;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class NetworkOwnerNetworkController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $networks = $request->user()->networks()
            ->with(['region', 'directorate', 'subDirectorate'])
            ->withAvg('ratings as average_rating', 'rating')
            ->withCount('ratings as ratings_count')
            ->orderByDesc('created_at')
            ->paginate(20);

        return response()->json([
            'success' => true,
            'data' => $networks->map(fn($n) => [
                'id' => $n->id,
                'code' => $n->code,
                'name' => $n->name,
                'slug' => $n->slug,
                'logo_url' => $n->logo_url,
                'cover_image_url' => $n->cover_image_url,
                'background_image_url' => $n->background_image_url,
                'region' => $n->region?->name,
                'region_id' => $n->region_id,
                'directorate' => $n->directorate?->name,
                'directorate_id' => $n->directorate_id,
                'sub_directorate' => $n->subDirectorate?->name,
                'sub_directorate_id' => $n->sub_directorate_id,
                'description' => $n->description,
                'phone' => $n->phone,
                'url' => $n->url,
                'status' => $n->status,
                'rejection_reason' => $n->rejection_reason,
                'average_rating' => (float) ($n->average_rating ?? 0),
                'ratings_count' => $n->ratings_count ?? 0,
                'sales_count' => $n->sales_count ?? 0,
                'is_featured' => (bool) $n->is_featured,
                'created_at' => $n->created_at->toDateTimeString(),
            ])->values(),
            'meta' => [
                'total' => $networks->total(),
                'current_page' => $networks->currentPage(),
                'last_page' => $networks->lastPage(),
            ],
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'region_id' => 'required|exists:regions,id',
            'directorate_id' => 'required|exists:directorates,id',
            'sub_directorate_id' => 'required|exists:sub_directorates,id',
            'description' => 'nullable|string|max:2000',
            'url' => 'nullable|url|max:255',
            'cover_image' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
            'background_image' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $data = $request->only(['name', 'region_id', 'directorate_id', 'sub_directorate_id', 'description', 'url']);
        $data['user_id'] = $request->user()->id;
        $data['slug'] = Str::slug($request->name) . '-' . uniqid();
        $data['status'] = 'pending';

        foreach (['cover_image', 'background_image'] as $img) {
            if ($request->hasFile($img)) {
                $data[$img] = $request->file($img)->store("networks/{$img}s", 'public');
            }
        }

        $network = Network::create($data);

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء الشبكة بنجاح، وهي الآن قيد المراجعة',
            'data' => $this->resource($network->fresh(['region', 'directorate', 'subDirectorate'])),
        ], 201);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $network = $request->user()->networks()->with(['region', 'directorate', 'subDirectorate'])->findOrFail($id);
        return response()->json(['success' => true, 'data' => $this->resource($network)]);
    }

    public function update(Request $request, int $id): JsonResponse
    {
        $network = $request->user()->networks()->findOrFail($id);

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:255',
            'region_id' => 'sometimes|required|exists:regions,id',
            'directorate_id' => 'sometimes|required|exists:directorates,id',
            'sub_directorate_id' => 'sometimes|required|exists:sub_directorates,id',
            'description' => 'nullable|string|max:2000',
            'url' => 'nullable|url|max:255',
            'cover_image' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
            'background_image' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $data = $request->only(['name', 'region_id', 'directorate_id', 'sub_directorate_id', 'description', 'url']);

        foreach (['cover_image', 'background_image'] as $img) {
            if ($request->hasFile($img)) {
                $data[$img] = $request->file($img)->store("networks/{$img}s", 'public');
            }
        }

        $network->update($data);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الشبكة بنجاح',
            'data' => $this->resource($network->fresh(['region', 'directorate', 'subDirectorate'])),
        ]);
    }

    private function resource(Network $network): array
    {
        return [
            'id' => $network->id,
            'code' => $network->code,
            'name' => $network->name,
            'slug' => $network->slug,
            'logo_url' => $network->logo_url,
            'cover_image_url' => $network->cover_image_url,
            'background_image_url' => $network->background_image_url,
            'region' => $network->region?->name,
            'region_id' => $network->region_id,
            'directorate' => $network->directorate?->name,
            'directorate_id' => $network->directorate_id,
            'sub_directorate' => $network->subDirectorate?->name,
            'sub_directorate_id' => $network->sub_directorate_id,
            'description' => $network->description,
            'phone' => $network->phone,
            'url' => $network->url,
            'status' => $network->status,
            'rejection_reason' => $network->rejection_reason,
            'average_rating' => (float) ($network->average_rating ?? 0),
            'ratings_count' => $network->ratings_count ?? 0,
            'sales_count' => $network->sales_count ?? 0,
            'is_featured' => (bool) $network->is_featured,
            'created_at' => $network->created_at->toDateTimeString(),
        ];
    }
}
