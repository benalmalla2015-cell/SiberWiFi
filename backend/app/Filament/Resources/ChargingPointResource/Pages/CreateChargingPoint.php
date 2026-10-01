<?php

namespace App\Filament\Resources\ChargingPointResource\Pages;

use App\Filament\Resources\ChargingPointResource;
use Filament\Resources\Pages\CreateRecord;

class CreateChargingPoint extends CreateRecord
{
    protected static string $resource = ChargingPointResource::class;
    protected function getRedirectUrl(): string { return $this->getResource()::getUrl('index'); }
}
