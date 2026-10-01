<?php

namespace App\Filament\Resources\UserResource\Widgets;

use App\Models\User;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class UserStats extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $todayCount = User::whereDate('created_at', today())->count();
        $weekCount  = User::whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])->count();
        $monthCount = User::whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)->count();

        $clients = User::where('type', 'client')->count();
        $owners  = User::where('type', 'network_owner')->count();
        $admins  = User::where('type', 'admin')->count();

        return [
            Stat::make('مستخدمي اليوم', number_format($todayCount))
                ->description(number_format($clients) . ' عميل')
                ->descriptionIcon('heroicon-m-user')
                ->color('primary'),
            Stat::make('مستخدمي الأسبوع', number_format($weekCount))
                ->description(number_format($owners) . ' صاحب شبكة')
                ->descriptionIcon('heroicon-m-users')
                ->color('info'),
            Stat::make('مستخدمي الشهر', number_format($monthCount))
                ->description(number_format($admins) . ' مشرف')
                ->descriptionIcon('heroicon-m-shield-check')
                ->color('success'),
        ];
    }
}
