<?php

namespace App\Filament\Resources;

use App\Filament\Resources\DirectorateResource\Pages;
use App\Models\Directorate;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class DirectorateResource extends Resource
{
    protected static ?string $model = Directorate::class;
    protected static ?int $navigationSort = 2;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-map'; }
    public static function getNavigationLabel(): string { return 'المديريات'; }
    public static function getNavigationGroup(): ?string { return 'الإعدادات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            \Filament\Schemas\Components\Section::make()->schema([
                Forms\Components\Select::make('region_id')
                    ->label('المحافظة')
                    ->relationship('region', 'name')
                    ->required()
                    ->searchable(),
                Forms\Components\TextInput::make('name')->label('اسم المديرية (عربي)')->required(),
                Forms\Components\TextInput::make('name_en')->label('اسم المديرية (إنجليزي)'),
                Forms\Components\Toggle::make('is_active')->label('نشطة')->default(true),
            ])->columns(2),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#')->sortable(),
                Tables\Columns\TextColumn::make('region.name')->label('المحافظة')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('name')->label('المديرية')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('name_en')->label('الاسم الإنجليزي')->placeholder('—'),
                Tables\Columns\TextColumn::make('networks_count')->label('الشبكات')->counts('networks'),
                Tables\Columns\IconColumn::make('is_active')->label('نشطة')->boolean(),
                Tables\Columns\TextColumn::make('created_at')->label('أُضيفت')->date()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('region_id')
                    ->label('المحافظة')
                    ->relationship('region', 'name'),
                Tables\Filters\TernaryFilter::make('is_active')->label('الحالة'),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('region_id');
    }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListDirectorates::route('/'),
            'create' => Pages\CreateDirectorate::route('/create'),
            'edit'   => Pages\EditDirectorate::route('/{record}/edit'),
        ];
    }
}
