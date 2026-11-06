<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccCardImport;
use App\Models\AccStockMovement;
use App\Services\AccContext;
use App\Services\AccStockException;
use App\Services\AccStockService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Stock reads + adjustments (PLAN §4: GET /stock, POST /stock/adjust).
 * Every read first reconciles router-generated cards (source=mikrotik)
 * so the inventory always reflects the platform's reality — the sync
 * is read-only on `cards` and idempotent.
 */
class AccStockController extends Controller
{
    public function __construct(private AccStockService $stock) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $this->stock->syncRouterCards($ctx);

        $rows = \App\Models\AccStock::with('category')
            ->where('network_owner_id', $ctx->ownerId)
            ->get()
            ->sortBy(fn ($s) => $s->category?->sort_order ?? 0)
            ->values();

        return response()->json([
            'success' => true,
            'data' => $rows->map(fn ($s) => [
                'category_id' => $s->category_id,
                'category_name' => $s->category?->name,
                'unit_label' => $s->category?->unit_label,
                'sell_price' => (float) ($s->category?->sell_price ?? 0),
                'qty' => (float) $s->qty,
                'avg_cost' => (float) $s->avg_cost,
                'stock_value' => round((float) $s->qty * (float) $s->avg_cost, 2),
                'is_active' => (bool) ($s->category?->is_active ?? false),
            ]),
            'totals' => [
                'qty' => (float) $rows->sum('qty'),
                'value' => round($rows->sum(fn ($s) => (float) $s->qty * (float) $s->avg_cost), 2),
            ],
        ]);
    }

    public function movements(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccStockMovement::with('category:id,name,unit_label')
            ->where('network_owner_id', $ctx->ownerId)
            ->latest('id');

        if ($cat = $request->query('category_id')) {
            $query->where('category_id', (int) $cat);
        }
        if ($type = $request->query('type')) {
            $query->where('type', $type);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(30)->through(fn (AccStockMovement $m) => [
                'id' => $m->id,
                'category_id' => $m->category_id,
                'category_name' => $m->category?->name,
                'unit_label' => $m->category?->unit_label,
                'type' => $m->type,
                'qty' => (float) $m->qty,
                'unit_cost' => (float) $m->unit_cost,
                'ref_type' => $m->ref_type,
                'ref_id' => $m->ref_id,
                'note' => $m->note,
                'created_at' => $m->created_at?->toISOString(),
            ]),
        ]);
    }

    public function adjust(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'category_id' => 'required|integer',
            'qty' => 'required|numeric|min:0',
            'note' => 'nullable|string|max:190',
        ]);

        try {
            $movement = $this->stock->adjust(
                $ctx, (int) $data['category_id'], (float) $data['qty'], $data['note'] ?? null
            );
        } catch (AccStockException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], $e->status);
        }

        return response()->json([
            'success' => true,
            'message' => 'تمت تسوية المخزون',
            'data' => ['movement_id' => $movement->id, 'qty' => (float) $movement->qty],
        ]);
    }

    /** Manual trigger for the router-card reconciliation. */
    public function sync(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $stats = $this->stock->syncRouterCards($ctx);

        return response()->json([
            'success' => true,
            'message' => $stats['imported'] > 0 || $stats['sold'] > 0
                ? "تم ترحيل {$stats['imported']} كرت راوتر للمخزون"
                : 'المخزون محدّث — لا كروت جديدة',
            'data' => $stats,
        ]);
    }

    /** CSV stock intake — file upload or pasted `csv` text. */
    public function import(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate([
            'file' => 'nullable|file|mimes:csv,txt|max:2048',
            'csv' => 'nullable|string|max:200000',
        ]);

        $content = null;
        $filename = 'paste';
        if ($request->hasFile('file')) {
            $content = file_get_contents($request->file('file')->getRealPath());
            $filename = $request->file('file')->getClientOriginalName();
        } elseif ($request->filled('csv')) {
            $content = (string) $request->input('csv');
        }

        if ($content === null || trim($content) === '') {
            return response()->json([
                'success' => false,
                'message' => 'أرفق ملف CSV أو الصق محتواه',
            ], 422);
        }

        $import = $this->stock->importCsv($ctx, $content, $filename);

        return response()->json([
            'success' => $import->status !== 'failed',
            'message' => "استيراد: {$import->imported_count} سطر، تخطّي {$import->skipped_count}",
            'data' => $import,
        ], $import->status === 'failed' ? 422 : 200);
    }

    public function imports(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        return response()->json([
            'success' => true,
            'data' => AccCardImport::where('network_owner_id', $ctx->ownerId)
                ->latest()->paginate(20),
        ]);
    }
}
