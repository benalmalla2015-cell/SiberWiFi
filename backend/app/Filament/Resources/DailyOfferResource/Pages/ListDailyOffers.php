<?php

namespace App\Filament\Resources\DailyOfferResource\Pages;

use App\Filament\Resources\DailyOfferResource;
use Filament\Actions;
use Filament\Resources\Pages\ListRecords;

class ListDailyOffers extends ListRecords
{
    protected static string $resource = DailyOfferResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Actions\CreateAction::make()->label('إضافة عرض يومي'),
        ];
    }
}
