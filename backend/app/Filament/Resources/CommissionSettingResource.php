<?php

namespace App\Filament\Resources;

use App\Filament\Resources\CommissionSettingResource\Pages;
use App\Models\CommissionSetting;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class CommissionSettingResource extends Resource
{
    protected static ?string $model = CommissionSetting::class;
    protected static ?int $navigationSort = 3;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-percent-badge'; }
    public static function getNavigationLabel(): string { return 'إعدادات العمولة'; }
    public static function getNavigationGroup(): ?string { return 'الإعدادات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\TextInput::make('name')
                ->label('اسم الإعداد')
                ->required(),
            Forms\Components\Select::make('type')
                ->label('نوع العمولة')
                ->options([
                    'app' => 'تطبيق',
                    'charging_point' => 'نقطة شحن',
                    'referral' => 'إحالة',
                ])
                ->required(),
            Forms\Components\Select::make('region_type')
                ->label('المنطقة')
                ->options([
                    'north' => 'الشمال',
                    'south' => 'الجنوب',
                ])
                ->nullable(),
            Forms\Components\TextInput::make('fixed_amount')
                ->label('المبلغ الثابت')
                ->numeric()
                ->default(0)
                ->minValue(0)
                ->suffix('ر.ي'),
            Forms\Components\TextInput::make('percentage')
                ->label('النسبة المئوية %')
                ->numeric()
                ->default(0)
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
                Tables\Columns\TextColumn::make('name')->label('الاسم')->searchable(),
                Tables\Columns\TextColumn::make('type')->label('النوع'),
                Tables\Columns\TextColumn::make('region_type')->label('المنطقة'),
                Tables\Columns\TextColumn::make('fixed_amount')->label('المبلغ الثابت')->suffix(' ر.ي'),
                Tables\Columns\TextColumn::make('percentage')->label('النسبة')->suffix('%'),
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
            'index' => Pages\ListCommissionSettings::route('/'),
            'create' => Pages\CreateCommissionSetting::route('/create'),
            'edit' => Pages\EditCommissionSetting::route('/{record}/edit'),
        ];
    }
}
