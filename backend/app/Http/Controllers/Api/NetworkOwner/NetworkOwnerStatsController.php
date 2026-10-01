<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\CardCategory;
use App\Models\Transaction;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NetworkOwnerStatsController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user     = $request->user();
        $period   = $request->query('period', 'monthly');
        $networks = $user->networks()->pluck('id')->toArray();

        $query = Transaction::whereIn('network_id', $networks)->where('status', 'completed');

        [$chartData, $label] = match ($period) {
            'week', 'daily' => $this->dailyData($query->clone()),
            'year', 'monthly' => $this->monthlyData($query->clone()),
            default => $this->weeklyData($query->clone()),
        };

        $totalSales = (float) (clone $query)->sum('total_amount');
        $totalTransactions = (int) (clone $query)->count();

        $topCategories = CardCategory::whereIn('network_id', $networks)
            ->withCount(['cards as sold_count' => fn($q) => $q->where('status', 'sold')])
            ->orderByDesc('sold_count')
            ->limit(5)
            ->get()
            ->map(fn($c) => [
                'id'         => $c->id,
                'name'       => $c->name,
                'sold_count' => $c->sold_count,
                'price'      => (float) $c->price,
            ]);

        $totalCards = Transaction::whereIn('network_id', $networks)
            ->where('status', 'completed')
            ->sum('quantity');

        return response()->json([
            'success' => true,
            'data'    => [
                'period'         => $period,
                'chart_label'    => $label,
                'chart_data'     => $chartData,
                'top_categories' => $topCategories,
                'total_cards'    => (int) $totalCards,
                'total_sales'    => $totalSales,
                'total_transactions' => $totalTransactions,
                'available_balance' => (float) $user->available_balance,
                'frozen_balance'    => (float) $user->frozen_balance,
                'total_earnings'    => $totalSales,
            ],
        ]);
    }

    private function dailyData($query): array
    {
        $rows = $query->whereDate('created_at', '>=', now()->subDays(6))
            ->selectRaw('DATE(created_at) as date, SUM(total_amount) as total')
            ->groupBy('date')->orderBy('date')->get();

        $labels = collect(range(6, 0))->map(fn($d) => now()->subDays($d)->format('m/d'));
        $data   = $labels->map(fn($l) => (float) ($rows->firstWhere('date', now()->subDays(6 - $labels->search($l))->format('Y-m-d'))?->total ?? 0));

        return [['labels' => $labels->values(), 'values' => $data->values()], 'يومي'];
    }

    private function weeklyData($query): array
    {
        $rows = $query->whereDate('created_at', '>=', now()->subWeeks(7))
            ->selectRaw('YEARWEEK(created_at, 1) as week, SUM(total_amount) as total')
            ->groupBy('week')->orderBy('week')->get();

        return [['labels' => $rows->pluck('week'), 'values' => $rows->pluck('total')->map(fn($v) => (float) $v)], 'أسبوعي'];
    }

    private function monthlyData($query): array
    {
        $rows = $query->whereYear('created_at', now()->year)
            ->selectRaw('MONTH(created_at) as month, SUM(total_amount) as total')
            ->groupBy('month')->orderBy('month')->get();

        $monthNames = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
        $labels = $rows->map(fn($r) => $monthNames[$r->month - 1]);
        $values = $rows->pluck('total')->map(fn($v) => (float) $v);

        return [['labels' => $labels->values(), 'values' => $values->values()], 'شهري'];
    }
}
