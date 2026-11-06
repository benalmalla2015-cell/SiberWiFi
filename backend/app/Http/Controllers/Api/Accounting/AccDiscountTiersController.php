<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccDiscountTier;
use App\Services\AccContext;
use App\Services\AccDiscountService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Discount/reward tiers (ACC-10, PLAN §2.4). Management CRUD +
 * a /match preview that shows which tiers a hypothetical document
 * would earn — the same resolution the document cycles run at
 * posting time. Config rows: deleted tiers stay live in already
 * posted documents via the discount_amount snapshots.
 */
class AccDiscountTiersController extends Controller
{
    public function __construct(private AccDiscountService $discounts) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $tiers = AccDiscountTier::where('network_owner_id', $ctx->ownerId)
            ->orderBy('mode')->orderBy('basis')
            ->orderByDesc('min')->orderBy('sort_order')->orderBy('id')
            ->get()
            ->map(fn (AccDiscountTier $t) => $this->serialize($t));

        return response()->json(['success' => true, 'data' => $tiers]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $this->rules($request);

        $tier = AccDiscountTier::create([
            'network_owner_id' => $ctx->ownerId,
            ...$data,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'تمت إضافة الشريحة',
            'data' => $this->serialize($tier),
        ], 201);
    }

    public function update(Request $request, int $tier): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccDiscountTier::where('network_owner_id', $ctx->ownerId)->find($tier);
        if ($model === null) {
            return response()->json(['success' => false, 'message' => 'الشريحة غير موجودة'], 404);
        }

        $model->update($this->rules($request, partial: true));

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الشريحة',
            'data' => $this->serialize($model),
        ]);
    }

    public function destroy(Request $request, int $tier): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccDiscountTier::where('network_owner_id', $ctx->ownerId)->find($tier);
        if ($model === null) {
            return response()->json(['success' => false, 'message' => 'الشريحة غير موجودة'], 404);
        }

        $model->delete();

        return response()->json(['success' => true, 'message' => 'تم حذف الشريحة']);
    }

    /**
     * Which tiers a document earns: {qty, amount} → matched rewards
     * per mode — the exact preview of what sale/order approval will
     * apply automatically.
     */
    public function match(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'qty' => 'required|numeric|min:0',
            'amount' => 'required|numeric|min:0',
        ]);

        return response()->json([
            'success' => true,
            'data' => $this->discounts->matchPreview(
                $ctx->ownerId,
                (float) $data['qty'],
                (float) $data['amount']
            ),
        ]);
    }

    private function rules(Request $request, bool $partial = false): array
    {
        $req = $partial ? 'sometimes' : 'required';
        $modes = implode(',', AccDiscountTier::MODES);
        $bases = implode(',', AccDiscountTier::BASES);
        $units = implode(',', AccDiscountTier::UNITS);

        return $request->validate([
            'mode' => "$req|string|in:$modes",
            'basis' => "$req|string|in:$bases",
            'min' => "$req|numeric|min:0",
            'max' => 'nullable|numeric|gt:0',
            'reward_value' => "$req|numeric|min:0",
            'reward_unit' => "sometimes|string|in:$units",
            'sort_order' => 'sometimes|integer|min:0',
            'is_active' => 'sometimes|boolean',
        ]);
    }

    private function serialize(AccDiscountTier $t): array
    {
        return [
            'id' => $t->id,
            'mode' => $t->mode,
            'mode_label' => AccDiscountTier::modeLabel($t->mode),
            'basis' => $t->basis,
            'min' => (float) $t->min,
            'max' => $t->max !== null ? (float) $t->max : null,
            'reward_value' => (float) $t->reward_value,
            'reward_unit' => $t->reward_unit,
            'sort_order' => $t->sort_order,
            'is_active' => $t->is_active,
            'created_at' => $t->created_at?->toISOString(),
        ];
    }
}
