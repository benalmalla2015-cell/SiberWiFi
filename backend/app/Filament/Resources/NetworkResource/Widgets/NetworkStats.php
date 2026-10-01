<?php

namespace App\Filament\Resources\NetworkResource\Widgets;

use App\Models\Network;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class NetworkStats extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $todayCount = Network::whereDate('created_at', today())->count();
        $weekCount  = Network::whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])->count();
        $monthCount = Network::whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)->count();

        $pendingCount = Network::where('status', 'pending')->count();
        $activeCount  = Network::where('status', 'active')->count();
        $featuredCount = Network::where('is_featured', true)->count();

        return [
            Stat::make('شبكات اليوم', number_format($todayCount))
                ->description($activeCount . ' نشطة')
                ->descriptionIcon('heroicon-m-wifi')
                ->color('primary'),
            Stat::make('شبكات الأسبوع', number_format($weekCount))
                ->description('منذ ' . now()->startOfWeek()->format('Y-m-d'))
                ->descriptionIcon('heroicon-m-calendar-days')
                ->color('info'),
            Stat::make('شبكات الشهر', number_format($monthCount))
                ->description(now()->format('F Y'))
                ->descriptionIcon('heroicon-m-calendar-date-range')
                ->color('success'),
            Stat::make('بانتظار المراجعة', number_format($pendingCount))
                ->description($featuredCount . ' مميزة')
                ->descriptionIcon('heroicon-m-clock')
                ->color($pendingCount > 0 ? 'warning' : 'gray'),
        ];
    }
}
