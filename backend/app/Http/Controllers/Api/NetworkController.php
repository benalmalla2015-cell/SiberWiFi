<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CardCategory;
use App\Models\DailyOffer;
use App\Models\Favorite;
use App\Models\Network;
use App\Models\NetworkRating;
use App\Models\Report;
use App\Services\CurrencyService;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class NetworkController extends Controller
{
    /**
     * Networks listing for the "الشبكات المتاحة" screen, supporting the
     * location filters: الكل / الشمال / الجنوب / حسب المحافظة / حسب
     * المديرية / الأقرب إليك.
     *
     * `scope`:
     *   - all     : no location restriction whatsoever.
     *   - north   : any network whose governorate belongs to the north region.
     *   - south   : any network whose governorate belongs to the south region.
     *   - nearest : (default) only networks in the user's own مديرية/محافظة.
     * `directorate_id` / `sub_directorate_id` further narrow the results
     * (حسب المحافظة / حسب المديرية) and take priority over `scope`.
     */
    public function index(Request $request): JsonResponse
    {
        $query = Network::with(['region', 'directorate', 'subDirectorate'])
            ->where('status', 'active')
            ->withAvg('ratings as average_rating', 'rating')
            ->withCount('ratings as ratings_count')
            ->withCount(['cards as available_cards_count' => fn ($query) => $query->where('status', 'available')])
            ->withExists(['cardCategories as has_available_advance' => fn ($query) => $query
                ->where('is_active', true)
                ->where('advance_enabled', true)
                ->where('advance_status', 'approved')
                ->whereColumn('advance_used_count', '<', 'advance_max_cards')]);

        $user = $request->user();
        $scope = $request->string('scope')->toString() ?: 'nearest';
        $directorateId = $request->integer('directorate_id') ?: null;
        $subDirectorateId = $request->integer('sub_directorate_id') ?: null;
        $regionId = $request->integer('region_id') ?: null;

        if ($subDirectorateId) {
            $query->where('sub_directorate_id', $subDirectorateId);
        } elseif ($directorateId) {
            $query->where('directorate_id', $directorateId);
        } elseif ($regionId) {
            $query->where('region_id', $regionId);
        } elseif (in_array($scope, ['north', 'south'], true)) {
            $query->whereHas('region', fn ($q) => $q->where('type', $scope));
        } elseif ($scope === 'all') {
            // no location filter
        } else { // nearest (default)
            if ($user?->sub_directorate_id) {
                $query->where('sub_directorate_id', $user->sub_directorate_id);
            } elseif ($user?->directorate_id) {
                $query->where('directorate_id', $user->directorate_id);
            } elseif ($user?->region_id) {
                $query->where('region_id', $user->region_id);
            }
        }

        if ($request->search) {
            $search = trim($request->search);
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', '%' . $search . '%')
                  ->orWhere('code', 'like', '%' . $search . '%');
            });
        }

        $networks = $query->orderByDesc('is_featured')->orderBy('name');

        // Full sync mode for offline caching in the customer app.
        if ($request->boolean('all')) {
            return response()->json([
                'success' => true,
                'data' => $networks->get()->map(fn($n) => $this->networkListResource($n, $request->user()?->id, $request->user()?->region_type))->values(),
            ]);
        }

        $paginated = $networks->paginate(20);

        return response()->json([
            'success' => true,
            'data' => $paginated->map(fn($n) => $this->networkListResource($n, $request->user()?->id, $request->user()?->region_type))->values(),
            'meta' => [
                'total' => $paginated->total(),
                'current_page' => $paginated->currentPage(),
                'last_page' => $paginated->lastPage(),
            ],
        ]);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $network = Network::with(['region', 'directorate', 'subDirectorate', 'chargingPoints', 'cardCategories'])
            ->where('status', 'active')
            ->findOrFail($id);

        $network->increment('views_count');

        $userId = $request->user()?->id;
        $isFavorite = $userId ? Favorite::where('user_id', $userId)->where('network_id', $id)->exists() : false;
        $isPinned = false; // pinning can be added later

        $networkCurrency = $network->region?->type ?? 'north';
        $buyerCurrency = $request->user()?->region_type ?? $networkCurrency;
        $currencyConverted = CurrencyService::isConversionNeeded($networkCurrency, $buyerCurrency);
        $activeOffers = $this->activeOffersForNetwork($network->id);

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $network->id,
                'code' => $network->code,
                'name' => $network->name,
                'slug' => $network->slug,
                'description' => $network->description,
                'phone' => $network->phone,
                'url' => $network->url,
                'cover_image_url' => $network->cover_image_url,
                'background_image_url' => $network->background_image_url,
                'region' => $network->region?->name,
                'directorate' => $network->directorate?->name,
                'sub_directorate' => $network->subDirectorate?->name,
                'average_rating' => (float) ($network->average_rating ?? 0),
                'ratings_count' => $network->ratings_count ?? 0,
                'sales_count' => $network->sales_count ?? 0,
                'is_favorite' => $isFavorite,
                'is_pinned' => $isPinned,
                'supports_credit' => $network->hasAvailableAdvance(),
                'currency_converted' => $currencyConverted,
                'currency_note' => $currencyConverted
                    ? 'أسعار هذه الشبكة بعملة ' . CurrencyService::currencyLabel($networkCurrency) . '، وسيتم تحويلها تلقائياً إلى ' . CurrencyService::currencyLabel($buyerCurrency) . ' عند الشراء حسب سعر الصرف المعتمد'
                    : null,
                'charging_points' => $network->chargingPoints->where('is_active', true)->values(),
                'categories' => $network->cardCategories->where('is_active', true)->map(function ($c) use ($currencyConverted, $networkCurrency, $buyerCurrency, $activeOffers) {
                    $offer = DailyOffer::pickForCategory($activeOffers, (int) $c->id);
                    return [
                        'id' => $c->id,
                        'name' => $c->name,
                        'speed' => $c->speed,
                        'duration' => $c->duration,
                        'duration_unit' => $c->duration_unit,
                        'price' => (float) $c->price,
                        'converted_price' => $currencyConverted ? CurrencyService::convert((float) $c->price, $networkCurrency, $buyerCurrency) : (float) $c->price,
                        'offer_price' => $offer ? CurrencyService::convert($offer->applyToUnitPrice((float) $c->price), $networkCurrency, $buyerCurrency) : null,
                        'discount_percent' => $offer?->effectiveDiscountPercent() ?? 0.0,
                        'offer_title' => $offer?->title,
                        'value' => (float) $c->value,
                        'currency_converted' => $currencyConverted,
                        'network_currency' => $networkCurrency,
                        'available_cards_count' => $c->cards()->where('status', 'available')->count(),
                        'advance_enabled' => (bool) $c->advance_enabled,
                        'advance_max_cards' => (int) $c->advance_max_cards,
                        'advance_used_count' => (int) $c->advance_used_count,
                        'advance_status' => $c->advance_status,
                        'advance_available' => max(0, (int) $c->advance_max_cards - (int) $c->advance_used_count),
                    ];
                })->values(),
            ],
        ]);
    }

    public function categories(Request $request, int $id): JsonResponse
    {
        $network = Network::with('region')->where('status', 'active')->findOrFail($id);

        $networkCurrency = $network->region?->type ?? 'north';
        $buyerCurrency = $request->user()?->region_type ?? $networkCurrency;
        $currencyConverted = CurrencyService::isConversionNeeded($networkCurrency, $buyerCurrency);
        $activeOffers = $this->activeOffersForNetwork($network->id);

        $categories = CardCategory::where('network_id', $network->id)
            ->where('is_active', true)
            ->orderBy('price')
            ->get()
            ->map(function ($c) use ($currencyConverted, $networkCurrency, $buyerCurrency, $activeOffers) {
                $offer = DailyOffer::pickForCategory($activeOffers, (int) $c->id);
                return [
                    'id' => $c->id,
                    'name' => $c->name,
                    'speed' => $c->speed,
                    'duration' => $c->duration,
                    'duration_unit' => $c->duration_unit,
                    'price' => (float) $c->price,
                    'converted_price' => $currencyConverted ? CurrencyService::convert((float) $c->price, $networkCurrency, $buyerCurrency) : (float) $c->price,
                    'offer_price' => $offer ? CurrencyService::convert($offer->applyToUnitPrice((float) $c->price), $networkCurrency, $buyerCurrency) : null,
                    'discount_percent' => $offer?->effectiveDiscountPercent() ?? 0.0,
                    'offer_title' => $offer?->title,
                    'value' => (float) $c->value,
                    'currency_converted' => $currencyConverted,
                    'network_currency' => $networkCurrency,
                    'available_cards_count' => $c->cards()->where('status', 'available')->count(),
                    'advance_enabled' => (bool) $c->advance_enabled,
                    'advance_max_cards' => (int) $c->advance_max_cards,
                    'advance_used_count' => (int) $c->advance_used_count,
                    'advance_status' => $c->advance_status,
                    'advance_available' => max(0, (int) $c->advance_max_cards - (int) $c->advance_used_count),
                ];
            });

        return response()->json([
            'success' => true,
            'data' => $categories,
            'currency_converted' => $currencyConverted,
            'currency_note' => $currencyConverted
                ? 'أسعار هذه الشبكة بعملة ' . CurrencyService::currencyLabel($networkCurrency) . '، وسيتم تحويلها تلقائياً إلى ' . CurrencyService::currencyLabel($buyerCurrency) . ' عند الشراء حسب سعر الصرف المعتمد'
                : null,
        ]);
    }

    public function rate(Request $request, int $id): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'rating' => 'required|integer|min:1|max:5',
            'review' => 'nullable|string|max:2000',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        $network = Network::where('status', 'active')->findOrFail($id);

        NetworkRating::updateOrCreate(
            ['user_id' => $user->id, 'network_id' => $network->id],
            ['rating' => $request->rating, 'review' => $request->review]
        );

        $this->updateNetworkRating($network);

        try {
            app(NotificationService::class)->send(
                $network->owner,
                'تقييم جديد',
                'قام ' . $user->name . ' بتقييم شبكتك "' . $network->name . '" بـ ' . $request->rating . ' نجوم.',
                ['type' => 'new_rating', 'network_id' => $network->id]
            );
        } catch (\Throwable $e) {
            \Log::warning('Rating notification failed: ' . $e->getMessage());
        }

        return response()->json(['success' => true, 'message' => 'تم إرسال تقييمك بنجاح']);
    }

    public function report(Request $request, int $id): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'type' => 'nullable|string|max:100',
            'subject' => 'nullable|string|max:255',
            'message' => 'required|string|max:5000',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        $network = Network::where('status', 'active')->findOrFail($id);

        $report = Report::create([
            'user_id' => $user->id,
            'network_id' => $network->id,
            'type' => $request->type,
            'subject' => $request->subject,
            'message' => $request->message,
            'status' => 'open',
        ]);

        try {
            app(NotificationService::class)->send(
                $network->owner,
                'بلاغ جديد',
                'قام ' . $user->name . ' بإرسال بلاغ على شبكتك "' . $network->name . '".',
                ['type' => 'new_report', 'report_id' => $report->id, 'network_id' => $network->id]
            );
        } catch (\Throwable $e) {
            \Log::warning('Report notification failed: ' . $e->getMessage());
        }

        return response()->json(['success' => true, 'message' => 'تم إرسال البلاغ بنجاح']);
    }

    public function toggleFavorite(Request $request, int $id): JsonResponse
    {
        $user = $request->user();
        $favorite = Favorite::where('user_id', $user->id)->where('network_id', $id)->first();

        if ($favorite) {
            $favorite->delete();
            return response()->json(['success' => true, 'message' => 'تمت إزالة الشبكة من المفضلة', 'is_favorite' => false]);
        }

        Favorite::create(['user_id' => $user->id, 'network_id' => $id]);
        return response()->json(['success' => true, 'message' => 'تمت إضافة الشبكة للمفضلة', 'is_favorite' => true]);
    }

    public function togglePin(Request $request, int $id): JsonResponse
    {
        return response()->json(['success' => false, 'message' => 'غير متاح حالياً'], 501);
    }

    public function favorites(Request $request): JsonResponse
    {
        $networks = Network::whereHas('favorites', fn($q) => $q->where('user_id', $request->user()->id))
            ->withAvg('ratings as average_rating', 'rating')
            ->withCount('ratings as ratings_count')
            ->where('status', 'active')
            ->orderBy('name')
            ->paginate(20);

        return response()->json([
            'success' => true,
            'data' => $networks->map(fn($n) => $this->networkListResource($n, $request->user()->id, $request->user()?->region_type))->values(),
            'meta' => [
                'total' => $networks->total(),
                'current_page' => $networks->currentPage(),
                'last_page' => $networks->lastPage(),
            ],
        ]);
    }

    private function networkListResource(Network $network, ?int $userId, ?string $buyerCurrency = null): array
    {
        $isFavorite = $userId ? Favorite::where('user_id', $userId)->where('network_id', $network->id)->exists() : false;
        $networkCurrency = $network->region?->type ?? 'north';
        $currencyConverted = $buyerCurrency ? CurrencyService::isConversionNeeded($networkCurrency, $buyerCurrency) : false;

        return [
            'id' => $network->id,
            'code' => $network->code,
            'name' => $network->name,
            'slug' => $network->slug,
            'logo_url' => $network->logo_url,
            'cover_image_url' => $network->cover_image_url,
            'region' => $network->region?->name,
            'region_id' => $network->region_id,
            'directorate' => $network->directorate?->name,
            'directorate_id' => $network->directorate_id,
            'sub_directorate' => $network->subDirectorate?->name,
            'sub_directorate_id' => $network->sub_directorate_id,
            'average_rating' => (float) ($network->average_rating ?? 0),
            'ratings_count' => $network->ratings_count ?? 0,
            'available_cards_count' => $network->available_cards_count ?? 0,
            'sales_count' => $network->sales_count ?? 0,
            'is_featured' => (bool) $network->is_featured,
            'supports_credit' => $network->hasAvailableAdvance(),
            'is_favorite' => $isFavorite,
            'currency' => $networkCurrency,
            'currency_converted' => $currencyConverted,
        ];
    }

    /**
     * Currently-active daily offers for a network, preloaded once so each
     * category row can be matched without per-row JSON queries.
     */
    private function activeOffersForNetwork(int $networkId): \Illuminate\Support\Collection
    {
        return DailyOffer::activeForNetwork($networkId)->get();
    }

    private function updateNetworkRating(Network $network): void
    {
        $avg = $network->ratings()->avg('rating') ?? 0;
        $count = $network->ratings()->count();
        $network->update([
            'average_rating' => round($avg, 2),
            'ratings_count' => $count,
        ]);
    }
}
