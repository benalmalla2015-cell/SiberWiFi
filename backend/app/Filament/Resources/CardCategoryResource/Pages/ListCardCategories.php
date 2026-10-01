<?php

namespace App\Filament\Resources\CardCategoryResource\Pages;

use App\Filament\Resources\CardCategoryResource;
use Filament\Resources\Pages\ListRecords;

class ListCardCategories extends ListRecords
{
    protected static string $resource = CardCategoryResource::class;
}
