<?php

namespace App\Filament\Widgets;

use App\Models\Network;
use App\Models\PayoutRequest;
use App\Models\Transaction;
use App\Models\User;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class StatsOverview extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $totalRevenue    = Transaction::where('status', 'completed')->sum('commission_amount');
        $todayRevenue    = Transaction::where('status', 'completed')->whereDate('created_at', today())->sum('commission_amount');
        $pendingPayouts  = PayoutRequest::where('status', 'pending')->sum('requested_amount');
        $pendingNetworks = Network::where('status', 'pending')->count();

        return [
            Stat::make('إجمالي المستخدمين', User::where('type', 'client')->count())
                ->description('عميل مسجل')
                ->descriptionIcon('heroicon-m-arrow-trending-up')
                ->color('success'),

            Stat::make('الشبكات النشطة', Network::where('status', 'active')->count())
                ->description($pendingNetworks . ' بانتظار المراجعة')
                ->color($pendingNetworks > 0 ? 'warning' : 'success'),

            Stat::make('إيرادات اليوم', number_format($todayRevenue) . ' ر.ي')
                ->description('إجمالي: ' . number_format($totalRevenue) . ' ر.ي')
                ->color('primary'),

            Stat::make('طلبات سحب معلقة', number_format($pendingPayouts) . ' ر.ي')
                ->description(PayoutRequest::where('status', 'pending')->count() . ' طلب')
                ->color(PayoutRequest::where('status', 'pending')->exists() ? 'warning' : 'gray'),

            Stat::make('مبيعات اليوم', Transaction::where('status', 'completed')->whereDate('created_at', today())->count())
                ->description('إجمالي: ' . Transaction::where('status', 'completed')->count())
                ->color('info'),

            Stat::make('أصحاب الشبكات', User::where('type', 'network_owner')->count())
                ->color('gray'),
        ];
    }
}
