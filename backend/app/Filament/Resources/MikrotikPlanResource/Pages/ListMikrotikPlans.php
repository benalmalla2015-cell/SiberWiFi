<?php

namespace App\Filament\Resources\MikrotikPlanResource\Pages;

use App\Filament\Resources\MikrotikPlanResource;
use Filament\Resources\Pages\ListRecords;
use Filament\Actions\CreateAction;

class ListMikrotikPlans extends ListRecords
{
    protected static string $resource = MikrotikPlanResource::class;

    protected function getHeaderActions(): array
    {
        return [CreateAction::make()->label('خطة جديدة')];
    }
}
