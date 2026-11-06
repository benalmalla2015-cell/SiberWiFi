<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Services\AccContext;
use App\Services\AccReportsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The reporting surface (ACC-09, PLAN §4 + §5) — read-only:
 * executive summary, 30-day trend, sales/POS/commission reports,
 * the daily collections statement behind the PDF, and the audit
 * trail. Every figure reconciles with the journal because the
 * service aggregates acc_journal_lines directly.
 */
class AccReportsController extends Controller
{
    public function __construct(private AccReportsService $reports) {}

    /** Executive summary — today + month-to-date + balances. */
    public function summary(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        return response()->json([
            'success' => true,
            'data' => $this->reports->summary($ctx),
        ]);
    }

    /** Daily sales/collections/expenses series (default 30 days). */
    public function trend(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate(['days' => 'nullable|integer|min:1|max:365']);

        return response()->json([
            'success' => true,
            'data' => $this->reports->trend($ctx, (int) $request->query('days', 30)),
        ]);
    }

    /** Sales book + journal reconciliation over a period. */
    public function sales(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate([
            'from' => 'nullable|date',
            'to' => 'nullable|date',
        ]);

        return response()->json([
            'success' => true,
            'data' => $this->reports->salesReport(
                $ctx, $request->query('from'), $request->query('to')
            ),
        ]);
    }

    /** Per-point strength analysis (default 30 days). */
    public function posPerformance(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate(['days' => 'nullable|integer|min:1|max:365']);

        return response()->json([
            'success' => true,
            'data' => $this->reports->posPerformance(
                $ctx, (int) $request->query('days', 30)
            ),
        ]);
    }

    /** Commission accruals + journal check, optional Y-m period. */
    public function commissions(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate(['period' => 'nullable|string|size:7']);

        return response()->json([
            'success' => true,
            'data' => $this->reports->commissionsReport(
                $ctx, $request->query('period')
            ),
        ]);
    }

    /** One day's collection register — feeds the كشف يومي PDF. */
    public function collectionsDaily(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate(['date' => 'nullable|date']);

        return response()->json([
            'success' => true,
            'data' => $this->reports->collectionsDaily(
                $ctx, $request->query('date')
            ),
        ]);
    }

    /** Append-only audit trail — filterable, paginated. */
    public function auditLog(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate([
            'action' => 'nullable|string|max:60',
            'entity' => 'nullable|string|max:60',
            'agent_id' => 'nullable|integer',
            'from' => 'nullable|date',
            'to' => 'nullable|date',
        ]);

        return response()->json([
            'success' => true,
            'data' => $this->reports->auditLog($ctx, $request->only(
                ['action', 'entity', 'agent_id', 'from', 'to']
            )),
        ]);
    }
}
