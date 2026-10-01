<?php

namespace App\Filament\Resources\WalletLogResource\Pages;

use App\Filament\Resources\WalletLogResource;
use App\Filament\Resources\WalletLogResource\Widgets\WalletLogStats;
use Filament\Resources\Pages\ListRecords;

class ListWalletLogs extends ListRecords
{
    protected static string $resource = WalletLogResource::class;

    public function getHeaderWidgets(): array
    {
        return [
            WalletLogStats::class,
        ];
    }
}
