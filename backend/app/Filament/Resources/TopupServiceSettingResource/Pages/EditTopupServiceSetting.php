<?php

namespace App\Filament\Resources\TopupServiceSettingResource\Pages;

use App\Filament\Resources\TopupServiceSettingResource;
use Filament\Resources\Pages\EditRecord;

class EditTopupServiceSetting extends EditRecord
{
    protected static string $resource = TopupServiceSettingResource::class;
    protected function getRedirectUrl(): string { return $this->getResource()::getUrl('index'); }
}
