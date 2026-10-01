<?php

namespace App\Filament\Resources\CashbackSettingResource\Pages;

use App\Filament\Resources\CashbackSettingResource;
use Filament\Resources\Pages\CreateRecord;

class CreateCashbackSetting extends CreateRecord
{
    protected static string $resource = CashbackSettingResource::class;
    protected function getRedirectUrl(): string { return $this->getResource()::getUrl('index'); }
}
