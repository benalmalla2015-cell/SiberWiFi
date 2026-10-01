<?php

namespace App\Filament\Resources\WalletLogResource\Widgets;

use App\Models\WalletLog;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class WalletLogStats extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $todayCredit = WalletLog::where('type', 'credit')->whereDate('created_at', today())->sum('amount') ?? 0;
        $weekCredit  = WalletLog::where('type', 'credit')->whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])->sum('amount') ?? 0;
        $monthCredit = WalletLog::where('type', 'credit')->whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)->sum('amount') ?? 0;

        $todayDebit = WalletLog::where('type', 'debit')->whereDate('created_at', today())->sum('amount') ?? 0;
        $pendingTopup = WalletLog::where('type', 'pending_topup')->count();

        return [
            Stat::make('إيداع اليوم', number_format($todayCredit) . ' ر.ي')
                ->description('رصيد مضاف')
                ->descriptionIcon('heroicon-m-arrow-down-circle')
                ->color('success'),
            Stat::make('إيداع الأسبوع', number_format($weekCredit) . ' ر.ي')
                ->description('منذ ' . now()->startOfWeek()->format('Y-m-d'))
                ->descriptionIcon('heroicon-m-calendar-days')
                ->color('info'),
            Stat::make('إيداع الشهر', number_format($monthCredit) . ' ر.ي')
                ->description(now()->format('F Y'))
                ->descriptionIcon('heroicon-m-calendar-date-range')
                ->color('primary'),
            Stat::make('خصم اليوم', number_format($todayDebit) . ' ر.ي')
                ->description($pendingTopup . ' طلب شحن معلق')
                ->descriptionIcon('heroicon-m-arrow-up-circle')
                ->color($todayDebit > 0 ? 'danger' : 'gray'),
        ];
    }
}
