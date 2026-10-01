<?php

namespace App\Filament\Resources;

use App\Filament\Resources\ChargingPointResource\Pages;
use App\Models\ChargingPoint;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class ChargingPointResource extends Resource
{
    protected static ?string $model = ChargingPoint::class;
    protected static ?int $navigationSort = 4;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-map-pin'; }
    public static function getNavigationLabel(): string { return 'نقاط الشحن'; }
    public static function getNavigationGroup(): ?string { return 'الشبكات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\Select::make('network_id')
                ->label('الشبكة')
                ->relationship('network', 'name')
                ->searchable()
                ->required(),
            Forms\Components\TextInput::make('name')->label('اسم النقطة')->required()->maxLength(255),
            Forms\Components\TextInput::make('phone')->label('رقم الهاتف')->maxLength(20),
            Forms\Components\TextInput::make('location')->label('الموقع / العنوان')->maxLength(500),
            Forms\Components\TextInput::make('working_hours')->label('ساعات العمل')->maxLength(255),
            Grid::make(2)->schema([
                Forms\Components\TextInput::make('latitude')->label('خط العرض')->numeric(),
                Forms\Components\TextInput::make('longitude')->label('خط الطول')->numeric(),
            ]),
            Forms\Components\Toggle::make('is_active')->label('نشطة / متوفرة')->default(true),
            Forms\Components\Toggle::make('is_approved')->label('معتمدة')->default(false),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('network.name')->label('الشبكة')->searchable(),
                Tables\Columns\TextColumn::make('name')->label('النقطة')->searchable(),
                Tables\Columns\TextColumn::make('phone')->label('الهاتف'),
                Tables\Columns\TextColumn::make('location')->label('الموقع'),
                Tables\Columns\TextColumn::make('working_hours')->label('ساعات العمل')->toggleable(isToggledHiddenByDefault: true),
                Tables\Columns\IconColumn::make('is_active')->label('نشطة / متوفرة')->boolean(),
                Tables\Columns\IconColumn::make('is_approved')->label('معتمدة')->boolean(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('network_id')->label('الشبكة')->relationship('network', 'name'),
                Tables\Filters\TernaryFilter::make('is_active')->label('نشطة'),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListChargingPoints::route('/'),
            'create' => Pages\CreateChargingPoint::route('/create'),
            'edit' => Pages\EditChargingPoint::route('/{record}/edit'),
        ];
    }
}
