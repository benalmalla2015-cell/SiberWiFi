<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccReturn;
use App\Services\AccContext;
use App\Services\AccStockException;
use App\Services\AccStockService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Returns register (PLAN §2.1): list + post. */
class AccReturnsController extends Controller
{
    public function __construct(private AccStockService $stock) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccReturn::with('category:id,name')
            ->where('network_owner_id', $ctx->ownerId)
            ->latest('id');

        if ($kind = $request->query('kind')) {
            $query->where('kind', $kind);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccReturn $r) => $this->serialize($r)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'kind' => ['required', Rule::in(AccReturn::KINDS)],
            'ref_type' => 'nullable|string|max:32',
            'ref_id' => 'nullable|integer',
            'category_id' => 'required|integer',
            'qty' => 'required|numeric|min:0.01',
            'amount' => 'nullable|numeric|min:0',
            'reason' => 'nullable|string|max:190',
            'date' => 'nullable|date',
        ]);

        try {
            $return = $this->stock->recordReturn($ctx, $data);
        } catch (AccStockException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], $e->status);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل المرتجع',
            'data' => $this->serialize($return->load('category:id,name')),
        ], 201);
    }

    private function serialize(AccReturn $r): array
    {
        return [
            'id' => $r->id,
            'kind' => $r->kind,
            'ref_type' => $r->ref_type,
            'ref_id' => $r->ref_id,
            'category_id' => $r->category_id,
            'category_name' => $r->category?->name,
            'qty' => (float) $r->qty,
            'amount' => (float) $r->amount,
            'reason' => $r->reason,
            'date' => $r->date?->toDateString(),
        ];
    }
}
