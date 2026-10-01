<?php

namespace App\Filament\Widgets;

use App\Models\Network;
use App\Models\Transaction;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class RegionStatsOverview extends StatsOverviewWidget
{
    protected ?string $heading = 'إحصائيات المناطق';

    protected int | array | null $columns = 4;

    protected static ?int $sort = 1;

    protected function getStats(): array
    {
        // Networks count by region
        $northNetworksCount = Network::whereHas('region', function ($query) {
            $query->where('type', 'north');
        })->count();

        $southNetworksCount = Network::whereHas('region', function ($query) {
            $query->where('type', 'south');
        })->count();

        // Total revenue by region
        $northTotalRevenue = Transaction::where('status', 'completed')
            ->whereHas('network', function ($query) {
                $query->whereHas('region', function ($q) {
                    $q->where('type', 'north');
                });
            })
            ->sum('commission_amount');

        $southTotalRevenue = Transaction::where('status', 'completed')
            ->whereHas('network', function ($query) {
                $query->whereHas('region', function ($q) {
                    $q->where('type', 'south');
                });
            })
            ->sum('commission_amount');

        // Weekly revenue by region
        $northWeeklyRevenue = Transaction::where('status', 'completed')
            ->whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])
            ->whereHas('network', function ($query) {
                $query->whereHas('region', function ($q) {
                    $q->where('type', 'north');
                });
            })
            ->sum('commission_amount');

        $southWeeklyRevenue = Transaction::where('status', 'completed')
            ->whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])
            ->whereHas('network', function ($query) {
                $query->whereHas('region', function ($q) {
                    $q->where('type', 'south');
                });
            })
            ->sum('commission_amount');

        // Monthly revenue by region
        $northMonthlyRevenue = Transaction::where('status', 'completed')
            ->whereBetween('created_at', [now()->startOfMonth(), now()->endOfMonth()])
            ->whereHas('network', function ($query) {
                $query->whereHas('region', function ($q) {
                    $q->where('type', 'north');
                });
            })
            ->sum('commission_amount');

        $southMonthlyRevenue = Transaction::where('status', 'completed')
            ->whereBetween('created_at', [now()->startOfMonth(), now()->endOfMonth()])
            ->whereHas('network', function ($query) {
                $query->whereHas('region', function ($q) {
                    $q->where('type', 'south');
                });
            })
            ->sum('commission_amount');

        return [
            Stat::make('عدد الشبكات (الشمال)', $northNetworksCount)
                ->description('منطقة الشمال')
                ->descriptionIcon('heroicon-m-globe-alt')
                ->color('primary'),

            Stat::make('عدد الشبكات (الجنوب)', $southNetworksCount)
                ->description('منطقة الجنوب')
                ->descriptionIcon('heroicon-m-globe-alt')
                ->color('success'),

            Stat::make('إجمالي الإيرادات (الشمال)', number_format($northTotalRevenue) . ' R.Y')
                ->description('منطقة الشمال')
                ->descriptionIcon('heroicon-m-currency-dollar')
                ->color('primary'),

            Stat::make('إجمالي الإيرادات (الجنوب)', number_format($southTotalRevenue) . ' R.Y')
                ->description('منطقة الجنوب')
                ->descriptionIcon('heroicon-m-currency-dollar')
                ->color('success'),

            Stat::make('إيرادات الأسبوع (الشمال)', number_format($northWeeklyRevenue) . ' R.Y')
                ->description('هذا الأسبوع')
                ->descriptionIcon('heroicon-m-calendar')
                ->color('info'),

            Stat::make('إيرادات الأسبوع (الجنوب)', number_format($southWeeklyRevenue) . ' R.Y')
                ->description('هذا الأسبوع')
                ->descriptionIcon('heroicon-m-calendar')
                ->color('info'),

            Stat::make('إيرادات الشهر (الشمال)', number_format($northMonthlyRevenue) . ' R.Y')
                ->description('هذا الشهر')
                ->descriptionIcon('heroicon-m-calendar-days')
                ->color('warning'),

            Stat::make('إيرادات الشهر (الجنوب)', number_format($southMonthlyRevenue) . ' R.Y')
                ->description('هذا الشهر')
                ->descriptionIcon('heroicon-m-calendar-days')
                ->color('warning'),
        ];
    }
}
