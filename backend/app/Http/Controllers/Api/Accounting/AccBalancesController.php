<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccAgent;
use App\Models\AccBalance;
use App\Models\AccCashBox;
use App\Models\AccDebt;
use App\Models\AccPosPoint;
use App\Models\AccSupplier;
use App\Services\AccContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Party balances (PLAN §4: GET /balances?party=…, Sprint ACC-10).
 * Read model over acc_balances — the journal-driven running
 * balance per party — enriched with names and, for POS parties,
 * their points/profit wallets so the balances screen shows every
 * number a point carries in one row.
 */
class AccBalancesController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $query = AccBalance::where('network_owner_id', $ctx->ownerId)
            ->orderBy('party_type')->orderBy('party_id');

        if ($type = $request->query('party')) {
            $query->where('party_type', $type);
        }

        $rows = $query->get();
        $names = $this->partyNames($ctx->ownerId, $rows);
        $posMeta = $this->posMeta($ctx->ownerId, $rows);

        return response()->json([
            'success' => true,
            'data' => $rows->map(fn (AccBalance $b) => [
                'party_type' => $b->party_type,
                'party_id' => $b->party_id,
                'party_name' => $names["{$b->party_type}:{$b->party_id}"]
                    ?? "طرف {$b->party_type}:{$b->party_id}",
                'balance' => (float) $b->balance,
                'points_balance' => $posMeta[$b->party_id]['points_balance'] ?? null,
                'profit_balance' => $posMeta[$b->party_id]['profit_balance'] ?? null,
                'updated_at' => $b->updated_at?->toISOString(),
            ])->values(),
        ]);
    }

    /** Batch-resolve display names for every listed party. */
    private function partyNames(int $ownerId, $rows): array
    {
        $ids = fn (string $type) => $rows
            ->where('party_type', $type)
            ->pluck('party_id')->filter()->unique()->values();

        $names = [];

        $posIds = $ids('pos');
        if ($posIds->isNotEmpty()) {
            $names += AccPosPoint::where('network_owner_id', $ownerId)
                ->whereIn('id', $posIds)->pluck('name', 'id')
                ->mapWithKeys(fn ($n, $id) => ["pos:$id" => $n])->all();
        }

        $distIds = $ids('distributor');
        if ($distIds->isNotEmpty()) {
            $names += AccAgent::where('network_owner_id', $ownerId)
                ->whereIn('id', $distIds)->pluck('display_name', 'id')
                ->mapWithKeys(fn ($n, $id) => ["distributor:$id" => $n])->all();
        }

        $boxIds = $ids('box');
        if ($boxIds->isNotEmpty()) {
            $names += AccCashBox::where('network_owner_id', $ownerId)
                ->whereIn('id', $boxIds)->pluck('name', 'id')
                ->mapWithKeys(fn ($n, $id) => ["box:$id" => $n])->all();
        }

        $supplierIds = $ids('supplier');
        if ($supplierIds->isNotEmpty()) {
            $names += AccSupplier::where('network_owner_id', $ownerId)
                ->whereIn('id', $supplierIds)->pluck('name', 'id')
                ->mapWithKeys(fn ($n, $id) => ["supplier:$id" => $n])->all();
        }

        // Named customer parties self-reference their acc_debts row.
        $customerIds = $ids('customer');
        if ($customerIds->isNotEmpty()) {
            $names += AccDebt::where('network_owner_id', $ownerId)
                ->whereIn('id', $customerIds)->pluck('party_name', 'id')
                ->mapWithKeys(fn ($n, $id) => ["customer:$id" => $n])->all();
        }
        $names['customer:0'] = 'عملاء (متفرق)';

        return $names;
    }

    /** POS wallets (points + profit) for pos parties in the list. */
    private function posMeta(int $ownerId, $rows): array
    {
        $posIds = $rows->where('party_type', 'pos')->pluck('party_id')
            ->filter()->unique()->values();
        if ($posIds->isEmpty()) {
            return [];
        }

        return AccPosPoint::where('network_owner_id', $ownerId)
            ->whereIn('id', $posIds)
            ->get(['id', 'points_balance', 'profit_balance'])
            ->mapWithKeys(fn (AccPosPoint $p) => [$p->id => [
                'points_balance' => (float) $p->points_balance,
                'profit_balance' => (float) $p->profit_balance,
            ]])
            ->all();
    }
}
