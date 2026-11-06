<?php

namespace App\Filament\Resources\MikrotikSubscriptionResource\Pages;

use App\Filament\Resources\MikrotikSubscriptionResource;
use Filament\Resources\Pages\ListRecords;

class ListMikrotikSubscriptions extends ListRecords
{
    protected static string $resource = MikrotikSubscriptionResource::class;

    protected function getHeaderActions(): array
    {
        return [
            \Filament\Actions\CreateAction::make()->label('منح اشتراك'),
        ];
    }
}
