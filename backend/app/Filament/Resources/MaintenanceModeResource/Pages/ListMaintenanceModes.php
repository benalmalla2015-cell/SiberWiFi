<?php

namespace App\Filament\Resources\MaintenanceModeResource\Pages;

use App\Filament\Resources\MaintenanceModeResource;
use Filament\Actions;
use Filament\Resources\Pages\ListRecords;

class ListMaintenanceModes extends ListRecords
{
    protected static string $resource = MaintenanceModeResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Actions\CreateAction::make()->label('إضافة تطبيق للصيانة'),
        ];
    }
}
