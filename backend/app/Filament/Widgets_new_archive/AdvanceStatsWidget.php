<?php

namespace App\Filament\Widgets;

use App\Models\Transaction;
use App\Models\User;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

/**
 * Dashboard statistics for the "سلفني" (advance) feature: total amount
 * still owed by customers, and how many distinct networks currently have
 * outstanding advances, as required on the main admin dashboard.
 */
class AdvanceStatsWidget extends StatsOverviewWidget
{
    protected function getStats(): array
    {
        $totalOutstanding = (float) User::sum('advance_balance');

        $networksWithAdvances = Transaction::outstandingAdvances()->distinct('network_id')->count('network_id');

        $pendingRequests = \App\Models\CardCategory::where('advance_status', 'pending')->count();

        return [
            Stat::make('إجمالي مبلغ السلف المستحقة', number_format($totalOutstanding) . ' ريال')
                ->description('مجموع سلف "سلفني" غير المسددة على جميع العملاء')
                ->icon('heroicon-o-banknotes')
                ->color('warning'),
            Stat::make('عدد الشبكات المتسلفة', $networksWithAdvances)
                ->description('شبكات لديها سلف نشطة لم تُسدد بعد')
                ->icon('heroicon-o-wifi')
                ->color('info'),
            Stat::make('طلبات تفعيل سلفة قيد المراجعة', $pendingRequests)
                ->description('بانتظار موافقة الإدارة')
                ->icon('heroicon-o-clock')
                ->color($pendingRequests > 0 ? 'danger' : 'success'),
        ];
    }
}
