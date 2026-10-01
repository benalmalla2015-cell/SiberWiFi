<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\Card;
use App\Models\NetworkRating;
use App\Models\Report;
use App\Models\Transaction;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NetworkOwnerDashboardController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $networkIds = $user->networks()->pluck('id')->toArray();

        $totalSales = Transaction::whereIn('network_id', $networkIds)
            ->where('status', 'completed')
            ->sum('total_amount');

        $todaySales = Transaction::whereIn('network_id', $networkIds)
            ->where('status', 'completed')
            ->whereDate('created_at', today())
            ->sum('total_amount');

        $totalTransactions = Transaction::whereIn('network_id', $networkIds)
            ->where('status', 'completed')
            ->count();

        $availableCards = Card::whereIn('network_id', $networkIds)
            ->where('status', 'available')
            ->count();

        $soldCards = Card::whereIn('network_id', $networkIds)
            ->where('status', 'sold')
            ->count();

        $unreadReports = Report::whereIn('network_id', $networkIds)
            ->where('status', 'open')
            ->count();

        $averageRating = NetworkRating::whereIn('network_id', $networkIds)
            ->avg('rating') ?? 0;

        $topRequestedCategories = Transaction::with(['network:id,name', 'category:id,name'])
            ->selectRaw('network_id, category_id, COUNT(*) as demand_count, COALESCE(SUM(quantity), 0) as quantity_sold')
            ->whereIn('network_id', $networkIds)
            ->where('status', 'completed')
            ->groupBy('network_id', 'category_id')
            ->orderByDesc('demand_count')
            ->get()
            ->groupBy('network_id')
            ->map(fn($categories) => $categories->take(3)->map(fn($category) => [
                'category_id' => $category->category_id,
                'category_name' => $category->category?->name,
                'count' => (int) $category->demand_count,
                'quantity' => (int) $category->quantity_sold,
            ])->values());

        $topSoldCategories = Card::with(['network:id,name', 'category:id,name'])
            ->selectRaw('network_id, category_id, COUNT(*) as sold_count')
            ->whereIn('network_id', $networkIds)
            ->where('status', 'sold')
            ->groupBy('network_id', 'category_id')
            ->orderByDesc('sold_count')
            ->get()
            ->groupBy('network_id')
            ->map(fn($categories) => $categories->take(3)->map(fn($category) => [
                'category_id' => $category->category_id,
                'category_name' => $category->category?->name,
                'count' => (int) $category->sold_count,
            ])->values());

        $categoryInsights = $user->networks()->select('id', 'name')->get()->map(fn($network) => [
            'network_id' => $network->id,
            'network_name' => $network->name,
            'most_requested' => $topRequestedCategories->get($network->id, []),
            'most_sold' => $topSoldCategories->get($network->id, []),
        ])->values();

        $recentTransactions = Transaction::with(['user:id,name', 'network:id,name', 'category:id,name,value'])
            ->whereIn('network_id', $networkIds)
            ->where('status', 'completed')
            ->latest()
            ->limit(5)
            ->get()
            ->map(fn(Transaction $transaction) => $this->transactionResource($transaction));

        return response()->json([
            'success' => true,
            'data' => [
                'user' => [
                    'name' => $user->name,
                    'balance' => (float) $user->balance,
                    'available_balance' => (float) $user->available_balance,
                    'frozen_balance' => (float) $user->frozen_balance,
                ],
                'stats' => [
                    'total_networks' => count($networkIds),
                    'total_sales' => (float) $totalSales,
                    'today_sales' => (float) $todaySales,
                    'total_transactions' => (int) $totalTransactions,
                    'available_cards' => (int) $availableCards,
                    'sold_cards' => (int) $soldCards,
                    'average_rating' => round((float) $averageRating, 2),
                    'open_reports' => (int) $unreadReports,
                ],
                'recent_transactions' => $recentTransactions,
                'category_insights' => $categoryInsights,
            ],
        ]);
    }

    public function transactions(Request $request): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id');
        $search = $request->input('search');
        $transactions = Transaction::with(['user:id,name', 'network:id,name', 'category:id,name,value'])
            ->whereIn('network_id', $networkIds)
            ->where('status', 'completed')
            ->when($request->filled('search'), function ($query) use ($search) {
                $query->where(function ($q) use ($search) {
                    $q->where('transaction_number', 'like', "%{$search}%")
                        ->orWhereHas('user', fn($uq) => $uq->where('name', 'like', "%{$search}%"));
                });
            })
            ->latest()
            ->paginate(20);

        return response()->json([
            'success' => true,
            'data' => $transactions->getCollection()
                ->map(fn(Transaction $transaction) => $this->transactionResource($transaction))
                ->values(),
            'meta' => [
                'total' => $transactions->total(),
                'current_page' => $transactions->currentPage(),
                'last_page' => $transactions->lastPage(),
            ],
        ]);
    }

    private function transactionResource(Transaction $transaction): array
    {
        return [
            'id' => $transaction->id,
            'transaction_number' => $transaction->transaction_number,
            'network_name' => $transaction->network?->name,
            'category_name' => $transaction->category?->name,
            'client_name' => $transaction->user?->name,
            'value' => (float) ($transaction->category?->value ?? 0),
            'price' => (float) $transaction->total_amount,
            'owner_amount' => (float) $transaction->network_owner_amount,
            'commission_amount' => (float) $transaction->commission_amount,
            'quantity' => $transaction->quantity,
            'created_at' => $transaction->created_at->toDateTimeString(),
        ];
    }
}
