<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccPurchase;
use App\Services\AccContext;
use App\Services\AccStockException;
use App\Services\AccStockService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Purchase register: listing + posting. A POST runs the whole
 * document cycle atomically inside AccStockService::recordPurchase —
 * register row, `in` movement, journal entry, audit.
 */
class AccPurchasesController extends Controller
{
    public function __construct(private AccStockService $stock) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccPurchase::with(['supplier:id,name', 'category:id,name'])
            ->where('network_owner_id', $ctx->ownerId)
            ->latest('id');

        if ($cat = $request->query('category_id')) {
            $query->where('category_id', (int) $cat);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccPurchase $p) => $this->serialize($p)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'supplier_id' => 'nullable|integer',
            'category_id' => 'required|integer',
            'invoice_no' => 'nullable|string|max:64',
            'qty' => 'required|numeric|min:0.01',
            'unit_price' => 'required|numeric|min:0',
            'currency' => 'nullable|string|max:8',
            'exchange_rate' => 'nullable|numeric|min:0.000001',
            'payment' => ['nullable', Rule::in(AccPurchase::PAYMENTS)],
            'date' => 'nullable|date',
            'note' => 'nullable|string|max:190',
        ]);

        try {
            $purchase = $this->stock->recordPurchase($ctx, $data);
        } catch (AccStockException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], $e->status);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل الشراء ودخول الكمية للمخزون',
            'data' => $this->serialize($purchase->load(['supplier:id,name', 'category:id,name'])),
        ], 201);
    }

    private function serialize(AccPurchase $p): array
    {
        return [
            'id' => $p->id,
            'supplier_id' => $p->supplier_id,
            'supplier_name' => $p->supplier?->name,
            'category_id' => $p->category_id,
            'category_name' => $p->category?->name,
            'invoice_no' => $p->invoice_no,
            'qty' => (float) $p->qty,
            'unit_price' => (float) $p->unit_price,
            'currency' => $p->currency,
            'exchange_rate' => (float) $p->exchange_rate,
            'total' => (float) $p->total,
            'payment' => $p->payment,
            'date' => $p->date?->toDateString(),
            'note' => $p->note,
        ];
    }
}
