<?php

namespace App\Filament\Widgets;

use App\Models\Transaction;
use App\Models\User;
use Filament\Widgets\ChartWidget;
use Illuminate\Support\Carbon;

class SalesChart extends ChartWidget
{
    protected static ?int $sort = 3;
    protected int|string|array $columnSpan = 'full';

    public function getHeading(): ?string { return 'المبيعات والمستخدمون الجدد (آخر 12 شهر)'; }

    protected function getData(): array
    {
        $salesData = [];
        $usersData = [];
        $labels    = [];

        for ($i = 11; $i >= 0; $i--) {
            $month    = Carbon::today()->startOfMonth()->subMonths($i);
            $labels[] = $month->translatedFormat('M Y') ?: $month->format('m/Y');

            $salesData[] = Transaction::where('status', 'completed')
                ->whereYear('created_at', $month->year)
                ->whereMonth('created_at', $month->month)
                ->count();

            $usersData[] = User::where('type', 'client')
                ->whereYear('created_at', $month->year)
                ->whereMonth('created_at', $month->month)
                ->count();
        }

        return [
            'datasets' => [
                [
                    'label'           => 'المبيعات',
                    'data'            => $salesData,
                    'backgroundColor' => '#1A2B6D',
                    'borderColor'     => '#1A2B6D',
                ],
                [
                    'label'           => 'المستخدمون الجدد',
                    'data'            => $usersData,
                    'backgroundColor' => '#E31E24',
                    'borderColor'     => '#E31E24',
                ],
            ],
            'labels' => $labels,
        ];
    }

    protected function getType(): string { return 'bar'; }
}
