<?php

namespace App\Filament\Resources\NetworkOwnerResource\Pages;

use App\Filament\Resources\NetworkOwnerResource;
use Filament\Resources\Pages\EditRecord;

class EditNetworkOwner extends EditRecord
{
    protected static string $resource = NetworkOwnerResource::class;

    private ?string $newPassword = null;

    protected function mutateFormDataBeforeFill(array $data): array
    {
        // Ensure the record is loaded with its user relationship
        $this->record->load('user');
        return $data;
    }

    protected function mutateFormDataBeforeSave(array $data): array
    {
        $this->newPassword = $data['new_password'] ?? null;
        unset($data['new_password']);
        return $data;
    }

    protected function afterSave(): void
    {
        if (filled($this->newPassword) && $this->record->user) {
            $this->record->user->password = $this->newPassword;
            $this->record->user->save();
            $this->record->user->tokens()->delete();
        }

        // Sync payout data to pending payout requests
        try {
            \App\Models\PayoutRequest::where('user_id', $this->record->user_id)
                ->whereIn('status', ['pending', 'approved'])
                ->update([
                    'payout_full_name' => $this->record->payout_full_name,
                    'payout_provider' => $this->record->payout_provider,
                    'payout_account_number' => $this->record->payout_account_number,
                ]);
        } catch (\Throwable $e) {
            \Log::warning('Failed to sync payout data in EditNetworkOwner: ' . $e->getMessage());
        }
    }

    protected function getRedirectUrl(): string { return $this->getResource()::getUrl('index'); }
}
