<?php

namespace App\Filament\Resources\UserResource\Pages;

use App\Filament\Resources\UserResource;
use Filament\Resources\Pages\EditRecord;

class EditUser extends EditRecord
{
    protected static string $resource = UserResource::class;

    private ?string $newPassword = null;

    protected function mutateFormDataBeforeSave(array $data): array
    {
        $this->newPassword = $this->data['password'] ?? null;
        unset($data['password']);
        return $data;
    }

    protected function afterSave(): void
    {
        if (filled($this->newPassword)) {
            $this->record->password = $this->newPassword;
            $this->record->save();
            $this->record->tokens()->delete();
        }
    }

    protected function mutateFormDataBeforeFill(array $data): array
    {
        $this->record->load('networkOwnerProfile');
        return $data;
    }

    protected function getRedirectUrl(): string
    {
        return $this->getResource()::getUrl('index');
    }
}
