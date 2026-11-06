<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Services\AccContext;
use App\Services\AccReportsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The journal browser (ACC-09, PLAN §4: GET /journal + /journal/{id})
 * — posted entries with their balanced legs. Read-only by nature:
 * entries are immutable (PLAN §2.3).
 */
class AccJournalController extends Controller
{
    public function __construct(private AccReportsService $reports) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate([
            'doc_type' => 'nullable|string|max:30',
            'from' => 'nullable|date',
            'to' => 'nullable|date',
        ]);

        return response()->json([
            'success' => true,
            'data' => $this->reports->journal($ctx, $request->only(
                ['doc_type', 'from', 'to']
            )),
        ]);
    }

    public function show(Request $request, int $entry): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $this->reports->journalEntry($ctx, $entry);

        if ($data === null) {
            return response()->json([
                'success' => false,
                'message' => 'القيد غير موجود',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => $data,
        ]);
    }
}
