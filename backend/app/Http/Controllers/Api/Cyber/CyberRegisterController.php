<?php

namespace App\Http\Controllers\Api\Cyber;

use App\Http\Controllers\Api\Cyber\Requests\CyberRegisterRequest;
use App\Http\Controllers\Controller;
use App\Services\CyberRegistrationService;
use Illuminate\Http\JsonResponse;

class CyberRegisterController extends Controller
{
    public function __construct(private CyberRegistrationService $registrations) {}

    /**
     * POST /api/cyber/register — first-time client enrolment.
     * Issues the permanent 74XXXXXXX SIM number.
     */
    public function register(CyberRegisterRequest $request): JsonResponse
    {
        $subscriber = $this->registrations->register(
            $request->validated(),
            $request->file('id_front_image'),
            $request->file('id_back_image'),
        );

        return response()->json([
            'success' => true,
            'message' => 'تم التسجيل بنجاح — هذا رقم شريحتك الدائم',
            'data' => [
                'sim_no' => $subscriber->sim_no,
                'full_name' => $subscriber->full_name,
                'status' => $subscriber->status,
            ],
        ], 201);
    }

    /**
     * GET /api/cyber/subscribers/{sim_no} — number lookup (agents, CYB-07).
     * Never exposes document file paths.
     */
    public function show(string $sim_no): JsonResponse
    {
        $subscriber = $this->registrations->findBySim($sim_no);

        if (! $subscriber) {
            return response()->json([
                'success' => false,
                'message' => 'رقم الشريحة غير موجود',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'sim_no' => $subscriber->sim_no,
                'full_name' => $subscriber->full_name,
                'status' => $subscriber->status,
                'directorate_id' => $subscriber->directorate_id,
                'sub_directorate_id' => $subscriber->sub_directorate_id,
                'document_review' => $subscriber->documents->first()?->review_status,
                'identity_status' => $subscriber->identity?->status,
                'created_at' => $subscriber->created_at?->toIso8601String(),
            ],
        ]);
    }
}
