<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Services\CyberBillingService;

/**
 * GET /api/cyber/packages (CYB-04) — active packages for the
 * subscriber/agent apps.
 */
class PackageController extends Controller
{
    public function index(CyberBillingService $billing)
    {
        $packages = $billing->packages()->map(fn ($p) => [
            'id' => $p->id,
            'name' => $p->name,
            'name_ar' => $p->name_ar,
            'duration_days' => $p->duration_days,
            'data_limit_gb' => $p->data_limit_gb === null ? null : (float) $p->data_limit_gb,
            'price' => (float) $p->price,
            'rate_limit' => $p->rate_limit,
        ]);

        return response()->json(['success' => true, 'data' => $packages]);
    }
}
