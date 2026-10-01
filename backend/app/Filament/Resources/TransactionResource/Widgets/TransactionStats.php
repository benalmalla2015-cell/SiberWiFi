<?php

namespace App\Filament\Resources\TransactionResource\Widgets;

use App\Models\Transaction;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class TransactionStats extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $todayQuery = Transaction::where('status', 'completed')->whereDate('created_at', today());
        $weekQuery  = Transaction::where('status', 'completed')->whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()]);
        $monthQuery = Transaction::where('status', 'completed')->whereMonth('created_at', now()->month)->whereYear('created_at', now()->year);

        return [
            Stat::make('مبيعات اليوم', number_format($todayQuery->count()))
                ->description(number_format($todayQuery->sum('total_amount')) . ' ر.ي')
                ->descriptionIcon('heroicon-m-shopping-cart')
                ->color('primary'),
            Stat::make('مبيعات الأسبوع', number_format($weekQuery->count()))
                ->description(number_format($weekQuery->sum('total_amount')) . ' ر.ي')
                ->descriptionIcon('heroicon-m-calendar-days')
                ->color('info'),
            Stat::make('مبيعات الشهر', number_format($monthQuery->count()))
                ->description(number_format($monthQuery->sum('total_amount')) . ' ر.ي')
                ->descriptionIcon('heroicon-m-calendar-date-range')
                ->color('success'),
        ];
    }
}
