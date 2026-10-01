<?php

namespace App\Filament\Widgets;

use App\Models\SupportTicket;
use Filament\Support\Icons\Heroicon;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class SupportStats extends StatsOverviewWidget
{
    protected ?string $heading = 'تذاكر الدعم الفني';

    protected int | array | null $columns = 3;

    protected static ?int $sort = 6;

    protected function getStats(): array
    {
        return [
            Stat::make('مفتوحة', SupportTicket::where('status', 'open')->count())
                ->description('تذاكر بانتظار الرد')
                ->descriptionIcon(Heroicon::ExclamationCircle)
                ->icon(Heroicon::Ticket)
                ->color('danger'),

            Stat::make('قيد المعالجة', SupportTicket::where('status', 'in_progress')->count())
                ->description('تذاكر تحت المعالجة')
                ->descriptionIcon(Heroicon::Clock)
                ->icon(Heroicon::Clock)
                ->color('warning'),

            Stat::make('مغلقة', SupportTicket::where('status', 'closed')->count())
                ->description('تذاكر تم حلها')
                ->descriptionIcon(Heroicon::CheckCircle)
                ->icon(Heroicon::CheckCircle)
                ->color('success'),
        ];
    }
}
