<?php

namespace App\Filament\Resources\CashbackSettingResource\Pages;

use App\Filament\Resources\CashbackSettingResource;
use Filament\Actions;
use Filament\Resources\Pages\ListRecords;

class ListCashbackSettings extends ListRecords
{
    protected static string $resource = CashbackSettingResource::class;
    protected function getHeaderActions(): array { return [Actions\CreateAction::make()->label('إضافة كاشباك')]; }
}
