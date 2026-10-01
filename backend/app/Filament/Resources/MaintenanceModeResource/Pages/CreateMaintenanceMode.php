<?php

namespace App\Filament\Resources\MaintenanceModeResource\Pages;

use App\Filament\Resources\MaintenanceModeResource;
use Filament\Resources\Pages\CreateRecord;

class CreateMaintenanceMode extends CreateRecord
{
    protected static string $resource = MaintenanceModeResource::class;

    protected function getRedirectUrl(): string
    {
        return $this->getResource()::getUrl('index');
    }
}
