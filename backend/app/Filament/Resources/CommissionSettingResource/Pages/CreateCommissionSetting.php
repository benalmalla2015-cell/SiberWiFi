<?php

namespace App\Filament\Resources\CommissionSettingResource\Pages;

use App\Filament\Resources\CommissionSettingResource;
use Filament\Resources\Pages\CreateRecord;

class CreateCommissionSetting extends CreateRecord
{
    protected static string $resource = CommissionSettingResource::class;
    protected function getRedirectUrl(): string { return $this->getResource()::getUrl('index'); }
}
