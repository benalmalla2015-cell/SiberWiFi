<?php

namespace App\Filament\Resources\ChargingPointResource\Pages;

use App\Filament\Resources\ChargingPointResource;
use Filament\Actions;
use Filament\Resources\Pages\EditRecord;

class EditChargingPoint extends EditRecord
{
    protected static string $resource = ChargingPointResource::class;
    protected function getHeaderActions(): array { return [Actions\DeleteAction::make()]; }
    protected function getRedirectUrl(): string { return $this->getResource()::getUrl('index'); }
}
