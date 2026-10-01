<?php

namespace App\Filament\Resources;

use App\Filament\Resources\SubDirectorateResource\Pages;
use App\Models\SubDirectorate;
use App\Models\Directorate;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class SubDirectorateResource extends Resource
{
    protected static ?string $model = SubDirectorate::class;
    protected static ?int $navigationSort = 6;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-map'; }
    public static function getNavigationLabel(): string { return 'المديريات الفرعية'; }
    public static function getNavigationGroup(): ?string { return 'المناطق'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\Select::make('directorate_id')
                ->label('المحافظة/المديرية')
                ->options(Directorate::pluck('name', 'id'))
                ->searchable()
                ->required(),
            Forms\Components\TextInput::make('name')
                ->label('الاسم')
                ->required()
                ->maxLength(255),
            Forms\Components\TextInput::make('name_en')
                ->label('الاسم (إنجليزي)')
                ->maxLength(255),
            Forms\Components\Toggle::make('is_active')->label('نشط')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#')->sortable(),
                Tables\Columns\TextColumn::make('name')->label('الاسم')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('name_en')->label('الاسم (إنجليزي)')->searchable(),
                Tables\Columns\TextColumn::make('directorate.name')->label('المحافظة')->sortable(),
                Tables\Columns\IconColumn::make('is_active')->label('نشط')->boolean(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\TernaryFilter::make('is_active')->label('نشط'),
                Tables\Filters\SelectFilter::make('directorate_id')
                    ->label('المحافظة')
                    ->options(Directorate::pluck('name', 'id')),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('name', 'asc')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListSubDirectorates::route('/'),
            'create' => Pages\CreateSubDirectorate::route('/create'),
            'edit' => Pages\EditSubDirectorate::route('/{record}/edit'),
        ];
    }
}
