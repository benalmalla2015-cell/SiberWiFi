<?php

namespace App\Filament\Widgets;

use App\Models\Transaction;
use App\Models\User;
use Filament\Widgets\ChartWidget;

class SalesUsersChart extends ChartWidget
{
    protected ?string $heading = 'المبيعات والمستخدمون الجدد (آخر 12 شهرًا)';

    protected int | string | array $columnSpan = 1;

    protected static ?int $sort = 8;

    protected function getType(): string
    {
        return 'bar';
    }

    protected function getData(): array
    {
        $labels = [];
        $sales = [];
        $users = [];

        for ($i = 11; $i >= 0; $i--) {
            $month = now()->subMonths($i);
            $labels[] = $month->format('m/Y');

            $sales[] = (float) Transaction::where('status', 'completed')
                ->whereYear('created_at', $month->year)
                ->whereMonth('created_at', $month->month)
                ->sum('total_amount');

            $users[] = (int) User::whereYear('created_at', $month->year)
                ->whereMonth('created_at', $month->month)
                ->count();
        }

        return [
            'labels' => $labels,
            'datasets' => [
                [
                    'label' => 'المبيعات',
                    'data' => $sales,
                    'backgroundColor' => 'rgba(99, 102, 241, 0.85)',
                    'borderColor' => '#6366f1',
                    'borderWidth' => 1,
                    'borderRadius' => 4,
                ],
                [
                    'label' => 'المستخدمون الجدد',
                    'data' => $users,
                    'backgroundColor' => 'rgba(236, 72, 153, 0.85)',
                    'borderColor' => '#ec4899',
                    'borderWidth' => 1,
                    'borderRadius' => 4,
                ],
            ],
        ];
    }

    protected function getOptions(): array
    {
        return [
            'scales' => [
                'x' => [
                    'grid' => ['color' => 'rgba(255,255,255,0.05)'],
                    'ticks' => ['color' => 'rgba(255,255,255,0.6)'],
                ],
                'y' => [
                    'beginAtZero' => true,
                    'grid' => ['color' => 'rgba(255,255,255,0.05)'],
                    'ticks' => ['color' => 'rgba(255,255,255,0.6)'],
                ],
            ],
            'plugins' => [
                'legend' => [
                    'labels' => ['color' => 'rgba(255,255,255,0.8)'],
                ],
                'tooltip' => [
                    'backgroundColor' => 'rgba(18,21,38,0.95)',
                    'titleColor' => '#fff',
                    'bodyColor' => '#fff',
                    'borderColor' => 'rgba(255,255,255,0.1)',
                    'borderWidth' => 1,
                ],
            ],
        ];
    }
}
