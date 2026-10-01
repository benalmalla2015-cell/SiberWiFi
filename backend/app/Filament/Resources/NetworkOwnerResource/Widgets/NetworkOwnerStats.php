<?php

namespace App\Filament\Resources\NetworkOwnerResource\Widgets;

use App\Models\NetworkOwner;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class NetworkOwnerStats extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $todayCount = NetworkOwner::whereDate('created_at', today())->count();
        $weekCount  = NetworkOwner::whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])->count();
        $monthCount = NetworkOwner::whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)->count();

        $todayApproved = NetworkOwner::where('is_approved', true)->whereDate('created_at', today())->count();

        return [
            Stat::make('تسجيلات اليوم', number_format($todayCount))
                ->description($todayApproved . ' معتمدة')
                ->descriptionIcon('heroicon-m-calendar')
                ->color('primary'),
            Stat::make('تسجيلات الأسبوع', number_format($weekCount))
                ->description('منذ ' . now()->startOfWeek()->format('Y-m-d'))
                ->descriptionIcon('heroicon-m-calendar-days')
                ->color('info'),
            Stat::make('تسجيلات الشهر', number_format($monthCount))
                ->description(now()->format('F Y'))
                ->descriptionIcon('heroicon-m-calendar-date-range')
                ->color('success'),
        ];
    }
}
