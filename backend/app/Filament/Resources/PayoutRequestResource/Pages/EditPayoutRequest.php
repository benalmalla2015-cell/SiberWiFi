<?php

namespace App\Filament\Resources\PayoutRequestResource\Pages;

use App\Filament\Resources\PayoutRequestResource;
use Filament\Resources\Pages\EditRecord;

class EditPayoutRequest extends EditRecord
{
    protected static string $resource = PayoutRequestResource::class;

    protected function mutateFormDataBeforeFill(array $data): array
    {
        try {
            $this->record->load(['user', 'user.networkOwnerProfile']);
            $profile = $this->record->user?->networkOwnerProfile;
            
            // Use profile data if request fields are empty (fallback to ensure data is always shown)
            $data['payout_full_name'] = $this->record->payout_full_name ?? $profile?->payout_full_name ?? null;
            $data['payout_provider'] = $this->record->payout_provider ?? $profile?->payout_provider ?? null;
            $data['payout_account_number'] = $this->record->payout_account_number ?? $profile?->payout_account_number ?? null;
        } catch (\Throwable $e) {
            \Log::error('Error loading payout request data: ' . $e->getMessage());
            $data['payout_full_name'] = $this->record->payout_full_name ?? null;
            $data['payout_provider'] = $this->record->payout_provider ?? null;
            $data['payout_account_number'] = $this->record->payout_account_number ?? null;
        }
        return $data;
    }
}
