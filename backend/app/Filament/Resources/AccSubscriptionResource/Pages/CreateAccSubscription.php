<?php

namespace App\Filament\Resources\AccSubscriptionResource\Pages;

use App\Filament\Resources\AccSubscriptionResource;
use App\Models\AccPlan;
use App\Models\AccSubscription;
use Filament\Resources\Pages\CreateRecord;

/**
 * Admin-granted subscription. A new running sub supersedes the
 * tenant's older trial/active row — mirrors API subscribe().
 */
class CreateAccSubscription extends CreateRecord
{
    protected static string $resource = AccSubscriptionResource::class;

    /**
     * An empty date means "default": start now, end after the plan
     * duration — same semantics as the API subscribe() path. A null
     * end with no plan is a perpetual grant, which is intended.
     */
    protected function mutateFormDataBeforeCreate(array $data): array
    {
        $data['starts_at'] ??= now();
        if (empty($data['ends_at']) && !empty($data['plan_id'])) {
            $days = AccPlan::find($data['plan_id'])?->duration_days;
            if ($days) {
                $data['ends_at'] = now()->addDays($days);
            }
        }
        return $data;
    }

    protected function afterCreate(): void
    {
        $sub = $this->record;
        if (!in_array($sub->status, ['trial', 'active'])) {
            return;
        }
        AccSubscription::where('network_owner_id', $sub->network_owner_id)
            ->where('id', '!=', $sub->id)
            ->whereIn('status', ['trial', 'active'])
            ->update(['status' => 'expired']);
    }
}
