<?php

namespace App\Filament\Widgets;

use App\Models\PayoutRequest;
use Filament\Support\Icons\Heroicon;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class WithdrawalStats extends StatsOverviewWidget
{
    protected ?string $heading = 'طلبات السحب والصرف';

    protected int | array | null $columns = 4;

    protected static ?int $sort = 3;

    protected function getStats(): array
    {
        $today = $this->amountBetween(now()->startOfDay(), now()->endOfDay());
        $week = $this->amountBetween(now()->startOfWeek(), now()->endOfWeek());
        $month = $this->amountBetween(now()->startOfMonth(), now()->endOfMonth());

        return [
            Stat::make('سحب اليوم', $this->fmt($today))
                ->description('إجمالي مبالغ طلبات سحب اليوم')
                ->descriptionIcon(Heroicon::ArrowTrendingUp)
                ->icon(Heroicon::Banknotes)
                ->color('primary')
                ->chart($this->trend(1)),

            Stat::make('سحب الأسبوع', $this->fmt($week))
                ->description('إجمالي مبالغ طلبات سحب الأسبوع')
                ->descriptionIcon(Heroicon::ArrowTrendingUp)
                ->icon(Heroicon::Banknotes)
                ->color('secondary')
                ->chart($this->trend(7)),

            Stat::make('سحب الشهر', $this->fmt($month))
                ->description('إجمالي مبالغ طلبات سحب الشهر')
                ->descriptionIcon(Heroicon::ArrowTrendingUp)
                ->icon(Heroicon::Banknotes)
                ->color('success')
                ->chart($this->trend(30)),

            Stat::make('قيد المراجعة', PayoutRequest::where('status', 'pending')->count())
                ->description('طلبات السحب بانتظار الموافقة')
                ->descriptionIcon(Heroicon::Clock)
                ->icon(Heroicon::Clock)
                ->color('warning'),

            Stat::make('تمت الموافقة', PayoutRequest::where('status', 'approved')->count())
                ->description('طلبات تمت الموافقة عليها')
                ->descriptionIcon(Heroicon::CheckCircle)
                ->icon(Heroicon::CheckCircle)
                ->color('info'),

            Stat::make('مكتملة', PayoutRequest::where('status', 'received')->count())
                ->description('طلبات تم استلامها بالكامل')
                ->descriptionIcon(Heroicon::CheckCircle)
                ->icon(Heroicon::CheckCircle)
                ->color('success'),

            Stat::make('مرفوضة', PayoutRequest::where('status', 'rejected')->count())
                ->description('طلبات السحب المرفوضة')
                ->descriptionIcon(Heroicon::ExclamationCircle)
                ->icon(Heroicon::ExclamationCircle)
                ->color('danger'),
        ];
    }

    protected function amountBetween(\DateTimeInterface $start, \DateTimeInterface $end): float
    {
        return (float) PayoutRequest::whereBetween('created_at', [$start, $end])->sum('amount');
    }

    protected function trend(int $days): array
    {
        $start = now()->subDays($days - 1)->startOfDay();
        $rows = PayoutRequest::query()->selectRaw('DATE(created_at) as date, SUM(amount) as total')
            ->where('created_at', '>=', $start)
            ->groupBy('date')
            ->pluck('total', 'date');

        $data = [];
        for ($i = $days - 1; $i >= 0; $i--) {
            $d = now()->subDays($i)->toDateString();
            $data[] = (float) ($rows[$d] ?? 0);
        }

        return $data;
    }

    protected function fmt(float $amount): string
    {
        return number_format($amount, 2);
    }
}
