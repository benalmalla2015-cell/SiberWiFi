<?php

namespace App\Filament\Resources\ChargingPointResource\Pages;

use App\Filament\Resources\ChargingPointResource;
use Filament\Actions;
use Filament\Resources\Pages\ListRecords;

class ListChargingPoints extends ListRecords
{
    protected static string $resource = ChargingPointResource::class;
    protected function getHeaderActions(): array { return [Actions\CreateAction::make()->label('إضافة نقطة شحن')]; }
}
