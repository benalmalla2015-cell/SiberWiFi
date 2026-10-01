<?php

namespace App\Filament\Resources\ReferralResource\Widgets;

use App\Models\Referral;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class ReferralStats extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $todayCount = Referral::whereDate('created_at', today())->count();
        $weekCount  = Referral::whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])->count();
        $monthCount = Referral::whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)->count();

        $todayCommission = Referral::whereDate('created_at', today())->sum('commission_amount') ?? 0;
        $paidCount = Referral::where('is_paid', true)->count();
        $unpaidCount = Referral::where('is_paid', false)->count();

        return [
            Stat::make('إحالات اليوم', number_format($todayCount))
                ->description(number_format($todayCommission) . ' ر.ي عمولة')
                ->descriptionIcon('heroicon-m-user-plus')
                ->color('primary'),
            Stat::make('إحالات الأسبوع', number_format($weekCount))
                ->description('منذ ' . now()->startOfWeek()->format('Y-m-d'))
                ->descriptionIcon('heroicon-m-calendar-days')
                ->color('info'),
            Stat::make('إحالات الشهر', number_format($monthCount))
                ->description(now()->format('F Y'))
                ->descriptionIcon('heroicon-m-calendar-date-range')
                ->color('success'),
            Stat::make('حالة الدفع', number_format($paidCount) . ' / ' . number_format($unpaidCount))
                ->description('مدفوعة / غير مدفوعة')
                ->descriptionIcon('heroicon-m-banknotes')
                ->color($unpaidCount > 0 ? 'warning' : 'gray'),
        ];
    }
}
