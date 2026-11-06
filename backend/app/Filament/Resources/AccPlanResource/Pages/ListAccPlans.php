<?php

namespace App\Filament\Resources\AccPlanResource\Pages;

use App\Filament\Resources\AccPlanResource;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ListRecords;

class ListAccPlans extends ListRecords
{
    protected static string $resource = AccPlanResource::class;

    protected function getHeaderActions(): array
    {
        return [CreateAction::make()->label('خطة جديدة')];
    }
}
