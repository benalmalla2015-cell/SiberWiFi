<?php

namespace App\Filament\Widgets;

use App\Models\Transaction;
use Filament\Support\Icons\Heroicon;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class RevenueStats extends StatsOverviewWidget
{
    protected ?string $heading = 'الإيرادات الزمنية';

    protected int | array | null $columns = 4;

    protected static ?int $sort = 2;

    protected function getStats(): array
    {
        $today = $this->revenueBetween(now()->startOfDay(), now()->endOfDay());
        $yesterday = $this->revenueBetween(now()->subDay()->startOfDay(), now()->subDay()->endOfDay());

        $week = $this->revenueBetween(now()->startOfWeek(), now()->endOfWeek());
        $lastWeek = $this->revenueBetween(now()->subWeek()->startOfWeek(), now()->subWeek()->endOfWeek());

        $month = $this->revenueBetween(now()->startOfMonth(), now()->endOfMonth());
        $lastMonth = $this->revenueBetween(now()->subMonth()->startOfMonth(), now()->subMonth()->endOfMonth());

        return [
            Stat::make('إيرادات اليوم', $this->fmt($today))
                ->description($this->changeLabel($today, $yesterday))
                ->descriptionIcon($today >= $yesterday ? Heroicon::ArrowTrendingUp : Heroicon::ArrowTrendingDown)
                ->icon(Heroicon::Sun)
                ->color($today >= $yesterday ? 'success' : 'danger')
                ->chart($this->trend(1)),

            Stat::make('إيرادات هذا الأسبوع', $this->fmt($week))
                ->description($this->changeLabel($week, $lastWeek))
                ->descriptionIcon($week >= $lastWeek ? Heroicon::ArrowTrendingUp : Heroicon::ArrowTrendingDown)
                ->icon(Heroicon::CalendarDays)
                ->color($week >= $lastWeek ? 'success' : 'danger')
                ->chart($this->trend(7)),

            Stat::make('إيرادات هذا الشهر', $this->fmt($month))
                ->description($this->changeLabel($month, $lastMonth))
                ->descriptionIcon($month >= $lastMonth ? Heroicon::ArrowTrendingUp : Heroicon::ArrowTrendingDown)
                ->icon(Heroicon::CalendarDays)
                ->color($month >= $lastMonth ? 'success' : 'danger')
                ->chart($this->trend(30)),

            Stat::make('إجمالي الإيرادات', $this->fmt(Transaction::where('status', 'completed')->sum('total_amount')))
                ->description('جميع المعاملات المكتملة')
                ->descriptionIcon(Heroicon::Banknotes)
                ->icon(Heroicon::Banknotes)
                ->color('info')
                ->chart($this->trend(90)),
        ];
    }

    protected function revenueBetween(\DateTimeInterface $start, \DateTimeInterface $end): float
    {
        return (float) Transaction::where('status', 'completed')
            ->whereBetween('created_at', [$start, $end])
            ->sum('total_amount');
    }

    protected function changeLabel(float $current, float $previous): string
    {
        if ($previous == 0) {
            return $current > 0 ? '▲ جديد' : '▬ لا تغيير';
        }

        $percent = round((($current - $previous) / $previous) * 100, 1);
        $icon = $percent >= 0 ? '▲' : '▼';

        return $icon . ' ' . abs($percent) . '% مقارنة بالفترة السابقة';
    }

    protected function trend(int $days): array
    {
        $start = now()->subDays($days - 1)->startOfDay();
        $rows = Transaction::query()->selectRaw('DATE(created_at) as date, SUM(total_amount) as total')
            ->where('status', 'completed')
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
        return number_format($amount, 2) . ' R.Y';
    }
}
