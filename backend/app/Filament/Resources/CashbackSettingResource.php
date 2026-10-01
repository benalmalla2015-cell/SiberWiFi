<?php

namespace App\Filament\Resources;

use App\Filament\Resources\CashbackSettingResource\Pages;
use App\Models\CashbackSetting;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class CashbackSettingResource extends Resource
{
    protected static ?string $model = CashbackSetting::class;
    protected static ?int $navigationSort = 2;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-arrow-uturn-left'; }
    public static function getNavigationLabel(): string { return 'إعدادات الكاشباك'; }
    public static function getNavigationGroup(): ?string { return 'الإعدادات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\TextInput::make('name')
                ->label('اسم إعداد الكاشباك')
                ->required()
                ->maxLength(255),
            Forms\Components\TextInput::make('min_amount')
                ->label('الحد الأدنى للمبلغ')
                ->required()
                ->numeric()
                ->prefix('ر.ي'),
            Forms\Components\TextInput::make('cashback_percent')
                ->label('نسبة الكاشباك %')
                ->required()
                ->numeric()
                ->minValue(0)
                ->maxValue(100)
                ->suffix('%'),
            Forms\Components\Toggle::make('is_active')->label('نشط')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('min_amount')->label('الحد الأدنى')->money('YER'),
                Tables\Columns\TextColumn::make('cashback_percent')->label('نسبة الكاشباك')->suffix('%'),
                Tables\Columns\IconColumn::make('is_active')->label('نشط')->boolean(),
                Tables\Columns\TextColumn::make('updated_at')->label('آخر تحديث')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\TernaryFilter::make('is_active')->label('نشط'),
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
            'index' => Pages\ListCashbackSettings::route('/'),
            'create' => Pages\CreateCashbackSetting::route('/create'),
            'edit' => Pages\EditCashbackSetting::route('/{record}/edit'),
        ];
    }
}
