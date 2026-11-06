<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccDamaged;
use App\Services\AccContext;
use App\Services\AccStockException;
use App\Services\AccStockService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Damaged/lost cards register (PLAN §2.1): list + post. */
class AccDamagedController extends Controller
{
    public function __construct(private AccStockService $stock) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        return response()->json([
            'success' => true,
            'data' => AccDamaged::with('category:id,name')
                ->where('network_owner_id', $ctx->ownerId)
                ->latest('id')
                ->paginate(25)
                ->through(fn (AccDamaged $d) => $this->serialize($d)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'category_id' => 'required|integer',
            'qty' => 'required|numeric|min:0.01',
            'unit_cost' => 'nullable|numeric|min:0',
            'reason' => 'nullable|string|max:190',
            'evidence_note' => 'nullable|string|max:190',
            'date' => 'nullable|date',
        ]);

        try {
            $damaged = $this->stock->recordDamaged($ctx, $data);
        } catch (AccStockException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], $e->status);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل التالف وخصمه من المخزون',
            'data' => $this->serialize($damaged->load('category:id,name')),
        ], 201);
    }

    private function serialize(AccDamaged $d): array
    {
        return [
            'id' => $d->id,
            'category_id' => $d->category_id,
            'category_name' => $d->category?->name,
            'qty' => (float) $d->qty,
            'unit_cost' => (float) $d->unit_cost,
            'reason' => $d->reason,
            'evidence_note' => $d->evidence_note,
            'date' => $d->date?->toDateString(),
        ];
    }
}
