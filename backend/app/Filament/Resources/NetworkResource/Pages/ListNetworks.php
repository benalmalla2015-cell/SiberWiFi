<?php

namespace App\Filament\Resources\NetworkResource\Pages;

use App\Filament\Resources\NetworkResource;
use App\Filament\Resources\NetworkResource\Widgets\NetworkStats;
use Filament\Actions;
use Filament\Resources\Pages\ListRecords;

class ListNetworks extends ListRecords
{
    protected static string $resource = NetworkResource::class;

    protected function getHeaderActions(): array { return [Actions\CreateAction::make()->label('إضافة شبكة')]; }

    public function getHeaderWidgets(): array
    {
        return [
            NetworkStats::class,
        ];
    }
}
