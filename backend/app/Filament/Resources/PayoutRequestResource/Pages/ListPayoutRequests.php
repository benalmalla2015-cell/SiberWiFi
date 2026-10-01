<?php

namespace App\Filament\Resources\PayoutRequestResource\Pages;

use App\Filament\Resources\PayoutRequestResource;
use App\Filament\Resources\PayoutRequestResource\Widgets\PayoutRequestStats;
use Filament\Resources\Pages\ListRecords;

class ListPayoutRequests extends ListRecords
{
    protected static string $resource = PayoutRequestResource::class;

    public function getHeaderWidgets(): array
    {
        return [
            PayoutRequestStats::class,
        ];
    }
}
