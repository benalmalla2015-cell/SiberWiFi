<?php

namespace App\Filament\Resources\CommissionSettingResource\Pages;

use App\Filament\Resources\CommissionSettingResource;
use Filament\Actions;
use Filament\Resources\Pages\EditRecord;

class EditCommissionSetting extends EditRecord
{
    protected static string $resource = CommissionSettingResource::class;
    protected function getHeaderActions(): array { return [Actions\DeleteAction::make()]; }
    protected function getRedirectUrl(): string { return $this->getResource()::getUrl('index'); }
}
