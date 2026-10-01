<?php

namespace App\Filament\Resources;

use App\Filament\Resources\ExchangeRateSettingResource\Pages;
use App\Models\ExchangeRateSetting;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class ExchangeRateSettingResource extends Resource
{
    protected static ?string $model = ExchangeRateSetting::class;
    protected static ?int $navigationSort = 4;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-currency-dollar'; }
    public static function getNavigationLabel(): string { return 'سعر الصرف'; }
    public static function getNavigationGroup(): ?string { return 'الإعدادات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\Select::make('base_currency')
                ->label('العملة الأساسية')
                ->options([
                    'north' => 'ريال يمني قديم (شمال)',
                    'south' => 'ريال يمني (جنوب)',
                ])
                ->required(),
            Forms\Components\TextInput::make('rate_percent')
                ->label('سعر الصرف (لكل 100 وحدة من العملة الأساسية)')
                ->required()
                ->numeric()
                ->minValue(1)
                ->helperText('مثال: إذا كانت العملة الأساسية شمال والقيمة 380، يعني 100 ريال شمال = 380 ريال جنوب'),
            Forms\Components\Textarea::make('description')
                ->label('ملاحظة / وصف')
                ->rows(2)
                ->nullable(),
            Forms\Components\Toggle::make('is_active')->label('نشط')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('base_currency')
                    ->label('العملة الأساسية')
                    ->formatStateUsing(fn ($state) => $state === 'north' ? 'شمال' : 'جنوب'),
                Tables\Columns\TextColumn::make('rate_percent')->label('سعر الصرف'),
                Tables\Columns\TextColumn::make('description')->label('ملاحظة')->limit(50),
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
            'index' => Pages\ListExchangeRateSettings::route('/'),
            'create' => Pages\CreateExchangeRateSetting::route('/create'),
            'edit' => Pages\EditExchangeRateSetting::route('/{record}/edit'),
        ];
    }
}
