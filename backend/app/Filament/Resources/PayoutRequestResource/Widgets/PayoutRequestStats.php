<?php

namespace App\Filament\Resources\PayoutRequestResource\Widgets;

use App\Models\PayoutRequest;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class PayoutRequestStats extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $todayAmount = PayoutRequest::whereDate('created_at', today())->sum('amount') ?? 0;
        $weekAmount  = PayoutRequest::whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])->sum('amount') ?? 0;
        $monthAmount = PayoutRequest::whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)->sum('amount') ?? 0;

        $pendingCount = PayoutRequest::where('status', 'pending')->count();
        $paidCount    = PayoutRequest::where('status', 'paid_unconfirmed')->orWhere('status', 'received')->count();

        return [
            Stat::make('طلبات اليوم', number_format($todayAmount) . ' ر.ي')
                ->description(PayoutRequest::whereDate('created_at', today())->count() . ' طلب')
                ->descriptionIcon('heroicon-m-calendar')
                ->color('primary'),
            Stat::make('طلبات الأسبوع', number_format($weekAmount) . ' ر.ي')
                ->description('منذ ' . now()->startOfWeek()->format('Y-m-d'))
                ->descriptionIcon('heroicon-m-calendar-days')
                ->color('info'),
            Stat::make('طلبات الشهر', number_format($monthAmount) . ' ر.ي')
                ->description(now()->format('F Y'))
                ->descriptionIcon('heroicon-m-calendar-date-range')
                ->color('success'),
            Stat::make('قيد المراجعة', number_format($pendingCount))
                ->description('طلب سحب')
                ->descriptionIcon('heroicon-m-clock')
                ->color($pendingCount > 0 ? 'warning' : 'gray'),
        ];
    }
}
