<?php

namespace App\Filament\Resources\NetworkOwnerResource\Pages;

use App\Filament\Resources\NetworkOwnerResource;
use App\Filament\Resources\NetworkOwnerResource\Widgets\NetworkOwnerStats;
use Filament\Resources\Pages\ListRecords;

class ListNetworkOwners extends ListRecords
{
    protected static string $resource = NetworkOwnerResource::class;

    public function getHeaderWidgets(): array
    {
        return [
            NetworkOwnerStats::class,
        ];
    }
}
