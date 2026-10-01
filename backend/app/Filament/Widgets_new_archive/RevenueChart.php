<?php

namespace App\Filament\Widgets;

use App\Models\Transaction;
use Filament\Widgets\ChartWidget;
use Illuminate\Support\Carbon;

class RevenueChart extends ChartWidget
{
    protected static ?int $sort = 2;
    protected int|string|array $columnSpan = 'full';

    public function getHeading(): ?string { return 'إيرادات آخر 30 يوم'; }

    protected function getData(): array
    {
        $data   = [];
        $labels = [];

        for ($i = 29; $i >= 0; $i--) {
            $date     = Carbon::today()->subDays($i);
            $labels[] = $date->format('d/m');
            $data[]   = (float) Transaction::where('status', 'completed')
                ->whereDate('created_at', $date)
                ->sum('commission_amount');
        }

        return [
            'datasets' => [
                [
                    'label'           => 'الإيرادات (ريال)',
                    'data'            => $data,
                    'backgroundColor' => 'rgba(26, 43, 109, 0.1)',
                    'borderColor'     => '#1A2B6D',
                    'fill'            => true,
                    'tension'         => 0.4,
                ],
            ],
            'labels' => $labels,
        ];
    }

    protected function getType(): string { return 'line'; }
}
