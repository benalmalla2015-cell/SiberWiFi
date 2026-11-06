<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccDebt;
use App\Models\AccDebtPayment;
use App\Services\AccContext;
use App\Services\AccMoneyException;
use App\Services\AccMoneyService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Debts + settlement (ACC-05, PLAN §2.3 + §4). `/debts` lists the
 * tenant's receivables/payables, POST creates one (optionally
 * booking the opening entry), `/debts/{id}/pay` settles atomically.
 * Distributors use the `/dist/debts` aliases (debts.* grant).
 */
class AccDebtsController extends Controller
{
    public function __construct(private AccMoneyService $money) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccDebt::withCount('payments')
            ->where('network_owner_id', $ctx->ownerId)
            ->latest();

        if ($status = $request->query('status')) {
            $query->where('status', $status);
        }
        if ($type = $request->query('party_type')) {
            $query->where('party_type', $type);
        }
        if ($request->boolean('due_only')) {
            $query->whereNotNull('due_date')->whereDate('due_date', '<=', now());
        }

        return response()->json([
            'success' => true,
            'data' => $query->paginate(25)->through(fn (AccDebt $d) => $this->serialize($d)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'party_type' => 'required|string|in:pos,distributor,customer,person,supplier',
            'party_id' => 'nullable|integer',
            'party_name' => 'nullable|string|max:190',
            'phone' => 'nullable|string|max:30',
            'amount_due' => 'required|numeric|min:0.01',
            'currency' => 'nullable|string|in:north,south',
            'due_date' => 'nullable|date',
            'post_entry' => 'nullable|boolean',
            'note' => 'nullable|string|max:190',
        ]);

        try {
            $debt = $this->money->createDebt($ctx, $data);
        } catch (AccMoneyException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل الدين',
            'data' => $this->serialize($debt),
        ], 201);
    }

    public function pay(Request $request, int $debt): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'amount' => 'required|numeric|min:0.01',
            'cash_box_id' => 'nullable|integer',
            'paid_at' => 'nullable|date',
            'note' => 'nullable|string|max:190',
        ]);

        try {
            $payment = $this->money->payDebt($ctx, $debt, $data);
        } catch (AccMoneyException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل السداد وترحيله',
            'data' => [
                'id' => $payment->id,
                'debt_id' => $payment->debt_id,
                'amount' => (float) $payment->amount,
                'base_amount' => (float) $payment->base_amount,
                'cash_box_id' => $payment->cash_box_id,
                'collection_id' => $payment->collection_id,
                'journal_entry_id' => $payment->journal_entry_id,
                'paid_at' => $payment->paid_at?->toISOString(),
                'debt' => $this->serialize($payment->debt()->withCount('payments')->first()),
            ],
        ]);
    }

    /** Payment history of one debt. */
    public function payments(Request $request, int $debt): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $payments = AccDebtPayment::where('network_owner_id', $ctx->ownerId)
            ->where('debt_id', $debt)
            ->latest('paid_at')
            ->get()
            ->map(fn (AccDebtPayment $p) => [
                'id' => $p->id,
                'amount' => (float) $p->amount,
                'base_amount' => (float) $p->base_amount,
                'cash_box_id' => $p->cash_box_id,
                'collection_id' => $p->collection_id,
                'journal_entry_id' => $p->journal_entry_id,
                'paid_at' => $p->paid_at?->toISOString(),
                'note' => $p->note,
            ]);

        return response()->json(['success' => true, 'data' => $payments]);
    }

    private function serialize(AccDebt $d): array
    {
        return [
            'id' => $d->id,
            'party_type' => $d->party_type,
            'party_id' => $d->party_id,
            'party_name' => $d->party_name,
            'phone' => $d->phone,
            'direction' => $d->isPayable() ? 'payable' : 'receivable',
            'amount_due' => (float) $d->amount_due,
            'amount_paid' => (float) $d->amount_paid,
            'remaining' => $d->remaining(),
            'currency' => $d->currency,
            'status' => $d->status,
            'due_date' => $d->due_date?->toDateString(),
            'payments_count' => $d->payments_count ?? $d->payments()->count(),
            'note' => $d->note,
            'created_at' => $d->created_at?->toISOString(),
        ];
    }

    private function fail(AccMoneyException $e): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => $e->getMessage(),
        ], $e->status);
    }
}
