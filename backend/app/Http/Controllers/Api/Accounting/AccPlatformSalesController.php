<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccAccount;
use App\Models\AccJournalEntry;
use App\Models\AccPostingMap;
use App\Services\AccContext;
use App\Services\AccPlatformException;
use App\Services\AccPlatformSalesService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * ACC-08 — customer-app sales posting (PLAN §4).
 *
 * GET  /platform-sales        lazy-sync then list the posted
 *                             card_purchase_platform entries.
 * POST /platform-sales/sync   manual run → stats.
 * GET  /posting-map           effective source→account mapping.
 * PUT  /posting-map           sparse JSON overlay per source
 *                             (account codes must exist in the chart).
 */
class AccPlatformSalesController extends Controller
{
    public function __construct(private AccPlatformSalesService $sales) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $stats = $this->sales->sync($ctx);

        $entries = AccJournalEntry::with('lines')
            ->where('network_owner_id', $ctx->ownerId)
            ->where('doc_type', 'card_purchase_platform')
            ->latest('id')
            ->paginate(30);

        return response()->json([
            'success' => true,
            'sync' => $stats,
            'data' => $entries->through(fn (AccJournalEntry $e) => [
                'id' => $e->id,
                'entry_no' => $e->entry_no,
                'doc_ref_id' => $e->doc_ref_id,
                'date' => $e->date?->toDateString(),
                'currency' => $e->currency,
                'exchange_rate' => (float) $e->exchange_rate,
                'memo' => $e->memo,
                'posted_at' => $e->posted_at?->toISOString(),
                'lines' => $e->lines->map(fn ($l) => [
                    'account_code' => $l->account_code,
                    'debit' => (float) $l->debit,
                    'credit' => (float) $l->credit,
                ])->values(),
            ]),
        ]);
    }

    /** Manual trigger for the platform-sale reconciliation. */
    public function sync(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $limit = (int) $request->input('limit', 200);
        $stats = $this->sales->sync($ctx, $limit);

        return response()->json([
            'success' => true,
            'message' => $stats['posted'] > 0
                ? "تم ترحيل {$stats['posted']} عملية بيع من التطبيق"
                : 'لا مبيعات جديدة — السجل محدّث',
            'data' => $stats,
        ]);
    }

    public function postingMap(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        AccAccount::ensureDefaultsFor($ctx->ownerId);

        $sources = collect(AccPostingMap::SOURCES)->map(fn (string $source) => [
            'source' => $source,
            'mapping' => AccPostingMap::accountsFor($ctx->ownerId, $source),
            'defaults' => AccPostingMap::DEFAULTS[$source] ?? [],
            'customized' => AccPostingMap::where('network_owner_id', $ctx->ownerId)
                ->where('source', $source)->where('is_active', true)->exists(),
        ])->values();

        return response()->json([
            'success' => true,
            'data' => $sources,
            'accounts' => AccAccount::where('network_owner_id', $ctx->ownerId)
                ->where('is_active', true)
                ->orderBy('code')
                ->get(['code', 'name', 'type']),
        ]);
    }

    public function updatePostingMap(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'source' => 'required|string|in:' . implode(',', AccPostingMap::SOURCES),
            'mapping' => 'required|array',
        ]);

        AccAccount::ensureDefaultsFor($ctx->ownerId);

        $mapping = array_intersect_key($data['mapping'], array_flip(AccPostingMap::MAP_KEYS));
        if ($mapping === []) {
            return response()->json([
                'success' => false,
                'message' => 'الربط فارغ — مفاتيح مدعومة: ' . implode(', ', AccPostingMap::MAP_KEYS),
            ], 422);
        }

        $codes = array_values(array_unique(array_map('strval', $mapping)));
        $found = AccAccount::where('network_owner_id', $ctx->ownerId)
            ->whereIn('code', $codes)->where('is_active', true)->pluck('code')->all();
        $missing = array_diff($codes, $found);
        if ($missing !== []) {
            return response()->json([
                'success' => false,
                'message' => 'حسابات غير موجودة في الدليل: ' . implode(', ', $missing),
            ], 422);
        }

        $row = AccPostingMap::updateOrCreate(
            ['network_owner_id' => $ctx->ownerId, 'source' => $data['source']],
            ['mapping' => $mapping, 'is_active' => true]
        );

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث ربط الترحيل',
            'data' => [
                'source' => $row->source,
                'mapping' => AccPostingMap::accountsFor($ctx->ownerId, $row->source),
            ],
        ]);
    }
}
