<?php

namespace App\Filament\Widgets;

use App\Models\WalletLog;
use Filament\Support\Icons\Heroicon;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class RechargeStats extends StatsOverviewWidget
{
    protected ?string $heading = 'عمليات الشحن';

    protected int | array | null $columns = 4;

    protected static ?int $sort = 5;

    protected function getStats(): array
    {
        $pending = WalletLog::where('type', 'pending_topup');
        $rejected = WalletLog::where('type', 'rejected_topup');

        return [
            Stat::make('طلبات الشحن المعلقة', $pending->count())
                ->description('بانتظار مراجعة الإدارة')
                ->descriptionIcon(Heroicon::Clock)
                ->icon(Heroicon::Clock)
                ->color('warning'),

            Stat::make('مبلغ الشحن المعلق', $this->fmt((float) $pending->sum('amount')))
                ->description('إجمالي المبالغ في الطلبات المعلقة')
                ->descriptionIcon(Heroicon::Banknotes)
                ->icon(Heroicon::Banknotes)
                ->color('warning')
                ->chart($this->trend('pending_topup', 7)),

            Stat::make('طلبات الشحن المرفوضة', $rejected->count())
                ->description('عدد طلبات الشحن المرفوضة')
                ->descriptionIcon(Heroicon::ExclamationCircle)
                ->icon(Heroicon::ExclamationCircle)
                ->color('danger'),

            Stat::make('مبلغ الشحن المرفوض', $this->fmt((float) $rejected->sum('amount')))
                ->description('إجمالي المبالغ المرفوضة')
                ->descriptionIcon(Heroicon::Banknotes)
                ->icon(Heroicon::Banknotes)
                ->color('danger')
                ->chart($this->trend('rejected_topup', 7)),
        ];
    }

    protected function trend(string $type, int $days): array
    {
        $start = now()->subDays($days - 1)->startOfDay();
        $rows = WalletLog::query()->selectRaw('DATE(created_at) as date, SUM(amount) as total')
            ->where('type', $type)
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
