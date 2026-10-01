<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Directorate;
use App\Models\Region;
use App\Models\SubDirectorate;
use App\Models\ExchangeRateSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RegionController extends Controller
{
    public function index(): JsonResponse
    {
        $regions = Region::where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'name', 'name_en', 'type']);

        return response()->json(['success' => true, 'data' => $regions]);
    }

    public function directorates(int $regionId): JsonResponse
    {
        $directorates = Directorate::where('region_id', $regionId)
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'region_id', 'name', 'name_en']);

        return response()->json(['success' => true, 'data' => $directorates]);
    }

    public function subDirectorates(int $directorateId): JsonResponse
    {
        $subDirectorates = SubDirectorate::where('directorate_id', $directorateId)
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'directorate_id', 'name', 'name_en']);

        return response()->json(['success' => true, 'data' => $subDirectorates]);
    }

    public function exchangeRate(): JsonResponse
    {
        $setting = ExchangeRateSetting::current();

        if (!$setting) {
            return response()->json([
                'success' => true,
                'data' => [
                    'base_currency' => 'north',
                    'rate_percent' => 100,
                    'note' => 'لم يتم تعيين سعر صرف بعد',
                ],
            ]);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'base_currency' => $setting->base_currency,
                'rate_percent' => (float) $setting->rate_percent,
                'north_label' => \App\Services\CurrencyService::currencyLabel('north'),
                'south_label' => \App\Services\CurrencyService::currencyLabel('south'),
                'description' => $setting->description,
            ],
        ]);
    }

    public function allGovernorates(): JsonResponse
    {
        $directorates = \App\Models\Directorate::with(['region:id,name'])
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'region_id', 'name', 'name_en']);

        return response()->json([
            'success' => true,
            'data' => $directorates->map(fn($d) => [
                'id' => $d->id,
                'region_id' => $d->region_id,
                'name' => $d->name,
                'name_en' => $d->name_en,
                'region' => $d->region?->name,
            ])->values(),
        ]);
    }

    public function allSubDirectorates(): JsonResponse
    {
        $subDirectorates = \App\Models\SubDirectorate::with(['directorate:id,name,region_id', 'directorate.region:id,name'])
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'directorate_id', 'name', 'name_en']);

        return response()->json([
            'success' => true,
            'data' => $subDirectorates->map(fn($s) => [
                'id' => $s->id,
                'directorate_id' => $s->directorate_id,
                'name' => $s->name,
                'name_en' => $s->name_en,
                'directorate' => $s->directorate?->name,
                'region' => $s->directorate?->region?->name,
            ])->values(),
        ]);
    }

}