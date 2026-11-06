<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccSale;
use App\Models\AccSaleItem;
use App\Services\AccContext;
use App\Services\AccDistException;
use App\Services\AccDistService;
use App\Services\AccWebhookService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The distributor surface (ACC-06, PLAN §4 + §5). A distributor
 * works the field: sees sellable stock with his daily remaining,
 * sells to POS points cash/credit, collects, and reads his own
 * report + commissions — every query tenant-scoped via AccContext
 * and every write atomic inside AccDistService.
 */
class AccDistController extends Controller
{
    public function __construct(
        private AccDistService $dist,
        private AccWebhookService $webhooks,
    ) {}

    /** Categories + daily remaining + POS balances + today's totals. */
    public function home(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        return response()->json([
            'success' => true,
            'data' => $this->dist->home($ctx),
        ]);
    }

    /** Cash/credit sale to a POS point — one atomic posting. */
    public function storeSale(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'pos_id' => 'required|integer',
            'items' => 'required|array|min:1',
            'items.*.category_id' => 'nullable|integer',
            'items.*.name' => 'nullable|string|max:190',
            'items.*.qty' => 'required|integer|min:1',
            'items.*.unit_price' => 'nullable|numeric|min:0',
            'items.*.unit_cost' => 'nullable|numeric|min:0',
            'payment_kind' => 'required|string|in:cash,credit,partial',
            'paid_amount' => 'nullable|numeric|min:0',
            'currency' => 'nullable|string|in:north,south',
            'cash_box_id' => 'nullable|integer',
            'due_date' => 'nullable|date',
            'distributor_id' => 'nullable|integer',
            'sold_at' => 'nullable|date',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ]);

        try {
            $sale = $this->dist->sale($ctx, $data);
        } catch (AccDistException $e) {
            return $this->fail($e);
        }

        // ACC-10 — sale.created webhook templates render after the
        // transaction committed; never inside the atomic cycle.
        $pos = $sale->pos;
        $notifications = $pos === null ? [] : $this->webhooks->dispatch(
            $ctx->ownerId,
            $ctx->agentId(),
            'sale.created',
            [
                'pos_name' => $pos->name,
                'party_name' => $pos->name,
                'sale_no' => $sale->sale_no,
                'total' => (float) $sale->total_amount,
                'paid' => (float) $sale->paid_amount,
                'currency' => $sale->currency,
                'date' => $sale->sold_at?->toDateString(),
            ],
            [$this->webhooks->posRecipient($pos)]
        );

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل البيع وترحيله',
            'data' => $this->serialize($sale),
            'notifications' => $notifications,
        ], 201);
    }

    /** The acting distributor's own sales register (managers: all). */
    public function sales(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccSale::with(['pos:id,name', 'items'])
            ->where('network_owner_id', $ctx->ownerId)
            ->latest('sold_at');

        if ($ctx->role === 'distributor' && $ctx->agentId() !== null) {
            $id = $ctx->agentId();
            $query->where(function ($w) use ($id) {
                $w->where('distributor_id', $id)
                    ->orWhere(function ($w2) use ($id) {
                        $w2->whereNull('distributor_id')->where('agent_id', $id);
                    });
            });
        }
        if ($posId = $request->query('pos_id')) {
            $query->where('pos_id', (int) $posId);
        }
        if ($kind = $request->query('payment_kind')) {
            $query->where('payment_kind', $kind);
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccSale $s) => $this->serialize($s)),
        ]);
    }

    /** Period report: sales/cash/credit/collections/debts + daily. */
    public function report(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate([
            'from' => 'nullable|date',
            'to' => 'nullable|date',
        ]);

        return response()->json([
            'success' => true,
            'data' => $this->dist->report(
                $ctx,
                $request->query('from'),
                $request->query('to')
            ),
        ]);
    }

    /** Commission periods — own rows for a distributor. */
    public function commissions(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate(['period' => 'nullable|string|size:7']);

        return response()->json([
            'success' => true,
            'data' => $this->dist->commissions($ctx, $request->query('period')),
        ]);
    }

    private function serialize(AccSale $s): array
    {
        return [
            'id' => $s->id,
            'sale_no' => $s->sale_no,
            'pos_id' => $s->pos_id,
            'pos_name' => $s->pos?->name,
            'distributor_id' => $s->distributor_id,
            'payment_kind' => $s->payment_kind,
            'total_amount' => (float) $s->total_amount,
            'discount_amount' => (float) ($s->discount_amount ?? 0),
            'paid_amount' => (float) $s->paid_amount,
            'credit_remaining' => $s->creditRemaining(),
            'currency' => $s->currency,
            'base_total' => (float) $s->base_total,
            'commission_amount' => (float) $s->commission_amount,
            'status' => $s->status,
            'debt_id' => $s->debt_id,
            'journal_entry_id' => $s->journal_entry_id,
            'sold_at' => $s->sold_at?->toISOString(),
            'note' => $s->note,
            'items' => $s->items->map(fn (AccSaleItem $i) => [
                'id' => $i->id,
                'category_id' => $i->category_id,
                'category_name' => $i->category_name,
                'qty' => $i->qty,
                'unit_price' => (float) $i->unit_price,
                'unit_cost' => (float) $i->unit_cost,
                'line_total' => (float) $i->line_total,
            ])->values(),
        ];
    }

    private function fail(AccDistException $e): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => $e->getMessage(),
        ], $e->status);
    }
}
