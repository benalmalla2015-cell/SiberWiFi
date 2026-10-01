<?php

namespace App\Filament\Widgets;

use App\Models\BankAccount;
use App\Models\ChargingPoint;
use App\Models\Network;
use App\Models\User;
use Filament\Support\Icons\Heroicon;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class EntityStats extends StatsOverviewWidget
{
    protected ?string $heading = 'المستخدمون والكيانات';

    protected int | array | null $columns = 4;

    protected static ?int $sort = 4;

    protected function getStats(): array
    {
        return [
            Stat::make('العملاء', User::where('type', 'client')->count())
                ->description('عدد العملاء المسجلين')
                ->descriptionIcon(Heroicon::Users)
                ->icon(Heroicon::Users)
                ->color('primary')
                ->chart($this->userTrend('client')),

            Stat::make('أصحاب الشبكات', User::where('type', 'network_owner')->count())
                ->description('عدد أصحاب الشبكات')
                ->descriptionIcon(Heroicon::RocketLaunch)
                ->icon(Heroicon::RocketLaunch)
                ->color('secondary')
                ->chart($this->userTrend('network_owner')),

            Stat::make('نقاط الشحن', ChargingPoint::count())
                ->description('عدد نقاط الشحن')
                ->descriptionIcon(Heroicon::DevicePhoneMobile)
                ->icon(Heroicon::DevicePhoneMobile)
                ->color('success')
                ->chart($this->chargingTrend()),

            Stat::make('الحسابات المصرفية', BankAccount::count())
                ->description('عدد الحسابات البنكية المسجلة')
                ->descriptionIcon(Heroicon::BuildingLibrary)
                ->icon(Heroicon::BuildingLibrary)
                ->color('info')
                ->chart($this->bankTrend()),

            Stat::make('الشبكات النشطة', Network::where('status', 'active')->count())
                ->description('الشبكات ذات الحالة النشطة')
                ->descriptionIcon(Heroicon::BuildingStorefront)
                ->icon(Heroicon::BuildingStorefront)
                ->color('warning')
                ->chart($this->networkTrend()),
        ];
    }

    protected function userTrend(string $type): array
    {
        $rows = User::query()->selectRaw('DATE(created_at) as date, COUNT(*) as total')
            ->where('type', $type)
            ->where('created_at', '>=', now()->subDays(6)->startOfDay())
            ->groupBy('date')
            ->pluck('total', 'date');

        return $this->fillTrend($rows, 7);
    }

    protected function chargingTrend(): array
    {
        $rows = ChargingPoint::query()->selectRaw('DATE(created_at) as date, COUNT(*) as total')
            ->where('created_at', '>=', now()->subDays(6)->startOfDay())
            ->groupBy('date')
            ->pluck('total', 'date');

        return $this->fillTrend($rows, 7);
    }

    protected function bankTrend(): array
    {
        $rows = BankAccount::query()->selectRaw('DATE(created_at) as date, COUNT(*) as total')
            ->where('created_at', '>=', now()->subDays(6)->startOfDay())
            ->groupBy('date')
            ->pluck('total', 'date');

        return $this->fillTrend($rows, 7);
    }

    protected function networkTrend(): array
    {
        $rows = Network::query()->selectRaw('DATE(created_at) as date, COUNT(*) as total')
            ->where('created_at', '>=', now()->subDays(6)->startOfDay())
            ->groupBy('date')
            ->pluck('total', 'date');

        return $this->fillTrend($rows, 7);
    }

    protected function fillTrend($rows, int $days): array
    {
        $data = [];
        for ($i = $days - 1; $i >= 0; $i--) {
            $d = now()->subDays($i)->toDateString();
            $data[] = (float) ($rows[$d] ?? 0);
        }
        return $data;
    }
}
