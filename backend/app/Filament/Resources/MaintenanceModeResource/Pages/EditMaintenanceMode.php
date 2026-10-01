<?php

namespace App\Filament\Resources\MaintenanceModeResource\Pages;

use App\Filament\Resources\MaintenanceModeResource;
use Filament\Actions;
use Filament\Resources\Pages\EditRecord;

class EditMaintenanceMode extends EditRecord
{
    protected static string $resource = MaintenanceModeResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Actions\DeleteAction::make()->label('حذف'),
        ];
    }

    protected function getRedirectUrl(): string
    {
        return $this->getResource()::getUrl('index');
    }
}
