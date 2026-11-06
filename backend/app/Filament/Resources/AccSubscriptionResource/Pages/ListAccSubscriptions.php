<?php

namespace App\Filament\Resources\AccSubscriptionResource\Pages;

use App\Filament\Resources\AccSubscriptionResource;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ListRecords;

class ListAccSubscriptions extends ListRecords
{
    protected static string $resource = AccSubscriptionResource::class;

    protected function getHeaderActions(): array
    {
        return [CreateAction::make()->label('منح اشتراك')];
    }
}
