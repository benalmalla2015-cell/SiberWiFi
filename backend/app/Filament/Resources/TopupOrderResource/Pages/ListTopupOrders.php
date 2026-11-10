<?php

namespace App\Filament\Resources\TopupOrderResource\Pages;

use App\Filament\Resources\TopupOrderResource;
use App\Filament\Widgets\TopupProfitStats;
use Filament\Resources\Pages\ListRecords;

class ListTopupOrders extends ListRecords
{
    protected static string $resource = TopupOrderResource::class;

    protected function getHeaderWidgets(): array
    {
        return [TopupProfitStats::class];
    }
}
