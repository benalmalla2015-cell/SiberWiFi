<?php

namespace App\Filament\Widgets;

use App\Models\SupportTicket;
use Filament\Widgets\ChartWidget;

class SupportTicketsChart extends ChartWidget
{
    protected ?string $heading = 'توزيع تذاكر الدعم الفني';

    protected int | string | array $columnSpan = 1;

    protected static ?int $sort = 9;

    protected function getType(): string
    {
        return 'doughnut';
    }

    protected function getData(): array
    {
        return [
            'labels' => ['مفتوحة', 'قيد المعالجة', 'مغلقة'],
            'datasets' => [
                [
                    'data' => [
                        SupportTicket::where('status', 'open')->count(),
                        SupportTicket::where('status', 'in_progress')->count(),
                        SupportTicket::where('status', 'closed')->count(),
                    ],
                    'backgroundColor' => [
                        'rgba(244, 63, 94, 0.85)',
                        'rgba(245, 158, 11, 0.85)',
                        'rgba(16, 185, 129, 0.85)',
                    ],
                    'borderColor' => ['#f43f5e', '#f59e0b', '#10b981'],
                    'borderWidth' => 1,
                ],
            ],
        ];
    }

    protected function getOptions(): array
    {
        return [
            'plugins' => [
                'legend' => [
                    'position' => 'right',
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
