<?php

namespace App\Filament\Resources\MikrotikSubscriptionResource\Pages;

use App\Filament\Resources\MikrotikSubscriptionResource;
use App\Models\MikrotikPlan;
use App\Models\MikrotikSubscription;
use Filament\Resources\Pages\CreateRecord;

/**
 * Admin-granted subscription (comp/goodwill/manual activation).
 * A new running sub supersedes the owner's older trial/active row —
 * mirrors the API subscribe() semantics.
 */
class CreateMikrotikSubscription extends CreateRecord
{
    protected static string $resource = MikrotikSubscriptionResource::class;

    /**
     * An empty date means "default": start now, end after the plan
     * duration — same semantics as the API subscribe() path. A null
     * end with no plan is a perpetual grant, which is intended.
     */
    protected function mutateFormDataBeforeCreate(array $data): array
    {
        $data['starts_at'] ??= now();
        if (empty($data['ends_at']) && !empty($data['plan_id'])) {
            $days = MikrotikPlan::find($data['plan_id'])?->duration_days;
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
        MikrotikSubscription::where('user_id', $sub->user_id)
            ->where('id', '!=', $sub->id)
            ->whereIn('status', ['trial', 'active'])
            ->update(['status' => 'expired']);
    }
}
