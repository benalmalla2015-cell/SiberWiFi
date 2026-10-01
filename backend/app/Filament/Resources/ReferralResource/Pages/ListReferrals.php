<?php

namespace App\Filament\Resources\ReferralResource\Pages;

use App\Filament\Resources\ReferralResource;
use App\Filament\Resources\ReferralResource\Widgets\ReferralStats;
use Filament\Resources\Pages\ListRecords;

class ListReferrals extends ListRecords
{
    protected static string $resource = ReferralResource::class;

    public function getHeaderWidgets(): array
    {
        return [
            ReferralStats::class,
        ];
    }
}
