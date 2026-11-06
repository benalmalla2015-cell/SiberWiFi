<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Models\CyberCoveragePoint;

/**
 * GET /api/cyber/coverage (CYB-08) — active CyberNet points for the
 * client app's coverage map. Public, read-only data.
 */
class CoverageController extends Controller
{
    public function index()
    {
        $points = CyberCoveragePoint::active()->get()->map(fn ($p) => [
            'id' => $p->id,
            'name' => $p->name,
            'city' => $p->city,
            'host_name' => $p->host_name,
            'latitude' => (float) $p->latitude,
            'longitude' => (float) $p->longitude,
        ]);

        return response()->json([
            'success' => true,
            'data' => [
                'ssid' => config('cyber.ssid'),
                'points' => $points,
            ],
        ]);
    }
}
