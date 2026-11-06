<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Controller;
use App\Services\CyberBillingService;
use App\Services\CyberUsageService;
use Illuminate\Http\Request;

/**
 * GET /api/cyber/usage/daily (CYB-09) — per-day consumption for the
 * client-app chart (7 or 30 days), device-bound like the other
 * subscriber endpoints.
 */
class UsageController extends Controller
{
    public function daily(Request $request, CyberBillingService $billing, CyberUsageService $usage)
    {
        $data = $request->validate([
            'sim_no' => ['required', 'string', 'max:16'],
            'device_id' => ['required', 'string', 'max:120'],
            'days' => ['nullable', 'integer', 'in:7,30'],
        ]);

        $subscriber = $billing->subscriberByDevice($data['sim_no'], $data['device_id']);
        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'الجهاز غير مرتبط بهذا الرقم',
            ], 403);
        }

        $report = $usage->dailyUsage(
            (int) $subscriber->id,
            $subscriber->sim_no,
            (int) ($data['days'] ?? 7)
        );

        return response()->json([
            'success' => true,
            'data' => ['sim_no' => $subscriber->sim_no] + $report,
        ]);
    }
}
