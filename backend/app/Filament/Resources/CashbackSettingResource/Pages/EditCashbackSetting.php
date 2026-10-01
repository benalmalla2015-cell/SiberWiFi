<?php

namespace App\Filament\Resources\CashbackSettingResource\Pages;

use App\Filament\Resources\CashbackSettingResource;
use Filament\Actions;
use Filament\Resources\Pages\EditRecord;

class EditCashbackSetting extends EditRecord
{
    protected static string $resource = CashbackSettingResource::class;
    protected function getHeaderActions(): array { return [Actions\DeleteAction::make()]; }
    protected function getRedirectUrl(): string { return $this->getResource()::getUrl('index'); }
}
