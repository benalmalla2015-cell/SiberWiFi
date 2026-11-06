<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccCardExchange;
use App\Models\AccWithdrawal;
use App\Services\AccContext;
use App\Services\AccOrderException;
use App\Services\AccPosAppService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The POS-agent surface (ACC-07, PLAN §4: /pos/*). A pos account is
 * pinned to its bound acc_pos_points row by the service — it sees
 * only its own balances, orders, withdrawals, exchanges and the
 * collections recorded against it.
 */
class AccPosAppController extends Controller
{
    public function __construct(private AccPosAppService $app) {}

    // ── Home + activity ──────────────────────────────────────────

    /** Balances + packages + stats + recent feed — one round-trip. */
    public function home(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        try {
            return response()->json([
                'success' => true,
                'data' => $this->app->home($ctx),
            ]);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }
    }

    /** Points + profit movements of the bound point (latest first). */
    public function ledger(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        try {
            return response()->json([
                'success' => true,
                'data' => $this->app->ledger($ctx),
            ]);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }
    }

    // ── Withdrawals ──────────────────────────────────────────────

    public function withdrawals(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        try {
            $rows = $this->app->myWithdrawals($ctx);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'data' => $rows->through(fn (AccWithdrawal $w) => $this->serializeWithdrawal($w)),
        ]);
    }

    public function storeWithdrawal(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'amount' => 'required|numeric|min:0.01',
            'receiver_name' => 'nullable|string|max:190',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ]);

        try {
            $w = $this->app->requestWithdrawal($ctx, $data);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال طلب السحب',
            'data' => $this->serializeWithdrawal($w),
        ], 201);
    }

    public function cancelWithdrawal(Request $request, int $withdrawal): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        try {
            $w = $this->app->cancelWithdrawal($ctx, $withdrawal);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إلغاء طلب السحب',
            'data' => $this->serializeWithdrawal($w),
        ]);
    }

    // ── Card exchange ────────────────────────────────────────────

    public function exchanges(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        try {
            $rows = $this->app->myExchanges($ctx);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'data' => $rows->through(fn (AccCardExchange $x) => $this->serializeExchange($x)),
        ]);
    }

    /** POST /pos/exchange-cards — instant points → cards redemption. */
    public function exchange(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'category_id' => 'required|integer',
            'qty' => 'required|integer|min:1',
            'note' => 'nullable|string|max:190',
            'idempotency_key' => 'nullable|string|max:120',
        ]);

        try {
            $x = $this->app->exchange($ctx, $data);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم استبدال النقاط بالكروت',
            'data' => $this->serializeExchange($x),
        ], 201);
    }

    // ── Serializers ──────────────────────────────────────────────

    private function serializeWithdrawal(AccWithdrawal $w): array
    {
        return [
            'id' => $w->id,
            'requester_type' => $w->requester_type,
            'requester_id' => $w->requester_id,
            'amount' => (float) $w->amount,
            'status' => $w->status,
            'receiver_name' => $w->receiver_name,
            'receipt_no' => $w->receipt_no,
            'note' => $w->note,
            'review_note' => $w->review_note,
            'reviewed_at' => $w->reviewed_at?->toISOString(),
            'paid_at' => $w->paid_at?->toISOString(),
            'created_at' => $w->created_at?->toISOString(),
        ];
    }

    private function serializeExchange(AccCardExchange $x): array
    {
        return [
            'id' => $x->id,
            'pos_id' => $x->pos_id,
            'category_id' => $x->category_id,
            'category_name' => $x->category_name,
            'qty' => $x->qty,
            'unit_price' => (float) $x->unit_price,
            'points_spent' => (float) $x->points_spent,
            'status' => $x->status,
            'note' => $x->note,
            'created_at' => $x->created_at?->toISOString(),
        ];
    }

    private function fail(AccOrderException $e): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => $e->getMessage(),
        ], $e->status);
    }
}
