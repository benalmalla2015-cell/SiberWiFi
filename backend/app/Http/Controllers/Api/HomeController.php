<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Advertisement;
use App\Models\DailyOffer;
use App\Models\Network;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class HomeController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $now = now();
        $user = $request->user();

        $sliders = Advertisement::where('is_active', true)
            ->where(function ($q) use ($now) {
                $q->whereNull('starts_at')->orWhere('starts_at', '<=', $now);
            })
            ->where(function ($q) use ($now) {
                $q->whereNull('ends_at')->orWhere('ends_at', '>=', $now);
            })
            ->orderBy('sort_order')
            ->get()
            ->map(fn($a) => [
                'id' => $a->id,
                'title' => $a->title,
                'image_url' => $a->image_url,
                'url' => $a->url,
                'position' => $a->position,
            ]);

        // Active offers first, then scheduled (upcoming) ones — upcoming
        // offers are announced as "قريباً" in the app but their discount is
        // NOT applied until they start (purchase path only uses active offers).
        $offers = DailyOffer::with('network:id,name')
            ->whereHas('network', fn ($query) => $query
                ->where('status', 'active'))
            ->where('is_active', true)
            ->where(function ($q) use ($now) {
                $q->whereNull('ends_at')->orWhere('ends_at', '>=', $now);
            })
            ->get()
            ->sortBy(fn($o) => $o->starts_at !== null && $o->starts_at->gt($now) ? 1 : 0)
            ->take(10)
            ->values()
            ->map(fn($o) => [
                'id' => $o->id,
                'title' => $o->title,
                'description' => $o->description,
                'discount_percent' => (float) $o->discount_percent,
                'network_name' => $o->network?->name,
                'network_id' => $o->network_id,
                'starts_at' => $o->starts_at?->toIso8601String(),
                'ends_at' => $o->ends_at?->toIso8601String(),
                'is_upcoming' => $o->starts_at !== null && $o->starts_at->gt($now),
                'apply_to_all_categories' => (bool) $o->apply_to_all_categories,
                'category_ids' => $o->category_ids ?? [],
            ]);

        // Top-selling networks: only networks that actually sold cards,
        // preferring the buyer's own directorate then governorate, ordered
        // strictly by descending card sales.
        $topNetworksQuery = Network::with(['region', 'directorate'])
            ->where('status', 'active')
            ->where('sales_count', '>', 0)
            ->orderByDesc('sales_count')
            ->limit(10);

        $topNetworks = collect();
        if ($user->sub_directorate_id) {
            $topNetworks = (clone $topNetworksQuery)
                ->where('sub_directorate_id', $user->sub_directorate_id)
                ->get();
        }
        if ($topNetworks->isEmpty() && $user->directorate_id) {
            $topNetworks = (clone $topNetworksQuery)
                ->where('directorate_id', $user->directorate_id)
                ->get();
        }
        if ($topNetworks->isEmpty() && $user->region_id) {
            $topNetworks = (clone $topNetworksQuery)
                ->where('region_id', $user->region_id)
                ->get();
        }

        $topNetworks = $topNetworks
            ->map(fn($n) => [
                'id' => $n->id,
                'name' => $n->name,
                'logo_url' => $n->logo_url,
                'cover_image_url' => $n->cover_image_url,
                'region' => $n->region?->name,
                'directorate' => $n->directorate?->name,
                'average_rating' => (float) ($n->average_rating ?? 0),
                'ratings_count' => $n->ratings_count ?? 0,
                'sales_count' => $n->sales_count ?? 0,
                'is_featured' => (bool) $n->is_featured,
            ]);

        return response()->json([
            'success' => true,
            'data' => [
                'sliders' => $sliders,
                'offers' => $offers,
                'top_networks' => $topNetworks,
            ],
        ]);
    }

    public function dailyOffers(Request $request): JsonResponse
    {
        $now = now();
        $user = $request->user();

        // Active offers first, then scheduled (upcoming) ones announced as
        // "قريباً". Discounts still only apply once the offer starts.
        $offers = DailyOffer::with('network:id,name')
            ->whereHas('network', fn ($query) => $query
                ->where('status', 'active'))
            ->where('is_active', true)
            ->where(function ($q) use ($now) {
                $q->whereNull('ends_at')->orWhere('ends_at', '>=', $now);
            })
            ->get()
            ->sortBy(fn($o) => $o->starts_at !== null && $o->starts_at->gt($now) ? 1 : 0)
            ->values()
            ->map(fn($o) => [
                'id' => $o->id,
                'title' => $o->title,
                'description' => $o->description,
                'discount_percent' => (float) $o->discount_percent,
                'network_name' => $o->network?->name,
                'network_id' => $o->network_id,
                'starts_at' => $o->starts_at?->toIso8601String(),
                'ends_at' => $o->ends_at?->toIso8601String(),
                'is_upcoming' => $o->starts_at !== null && $o->starts_at->gt($now),
                'apply_to_all_categories' => (bool) $o->apply_to_all_categories,
                'category_ids' => $o->category_ids ?? [],
            ]);

        return response()->json(['success' => true, 'data' => $offers]);
    }
}
