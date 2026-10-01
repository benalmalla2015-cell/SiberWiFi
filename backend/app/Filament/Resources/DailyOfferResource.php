<?php

namespace App\Filament\Resources;

use App\Filament\Resources\DailyOfferResource\Pages;
use App\Models\CardCategory;
use App\Models\DailyOffer;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class DailyOfferResource extends Resource
{
    protected static ?string $model = DailyOffer::class;
    protected static ?int $navigationSort = 3;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-gift'; }
    public static function getNavigationLabel(): string { return 'العروض اليومية'; }
    public static function getNavigationGroup(): ?string { return 'التطبيق'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\Select::make('network_id')
                ->label('الشبكة')
                ->relationship('network', 'name')
                ->searchable()
                ->required()
                ->reactive(),
            Forms\Components\TextInput::make('title')->label('عنوان العرض')->required()->maxLength(255),
            Forms\Components\Textarea::make('description')->label('الوصف')->rows(3),
            Forms\Components\TextInput::make('discount_percent')
                ->label('نسبة الخصم %')
                ->numeric()
                ->minValue(0)
                ->maxValue(100)
                ->default(0),
            Forms\Components\Toggle::make('apply_to_all_categories')
                ->label('تطبيق الخصم على جميع فئات الكروت')
                ->default(false)
                ->reactive(),
            Forms\Components\Select::make('category_ids')
                ->label('فئات الكروت المحددة')
                ->multiple()
                ->options(function (callable $get) {
                    $networkId = $get('network_id');
                    if (!$networkId) return [];
                    return CardCategory::where('network_id', $networkId)
                        ->where('is_active', true)
                        ->pluck('name', 'id')
                        ->toArray();
                })
                ->required(fn (callable $get) => $get('apply_to_all_categories') != true)
                ->hidden(fn (callable $get) => $get('apply_to_all_categories') == true)
                ->helperText('اختر فئة أو أكثر، أو فعّل تطبيق الخصم على جميع الفئات'),
            Grid::make(2)->schema([
                Forms\Components\DateTimePicker::make('starts_at')
                    ->label('تاريخ البدء')
                    ->helperText('اتركه فارغاً ليبدأ العرض فوراً'),
                Forms\Components\DateTimePicker::make('ends_at')
                    ->label('تاريخ الانتهاء')
                    ->helperText('اتركه فارغاً ليبقى العرض نشطاً بدون انتهاء'),
            ]),
            Forms\Components\Toggle::make('is_active')->label('نشط')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('network.name')->label('الشبكة')->searchable(),
                Tables\Columns\TextColumn::make('title')->label('العرض')->searchable(),
                Tables\Columns\TextColumn::make('discount_percent')->label('الخصم %')->suffix('%'),
                Tables\Columns\IconColumn::make('apply_to_all_categories')->label('كل الفئات')->boolean(),
                Tables\Columns\IconColumn::make('is_active')->label('نشط')->boolean(),
                Tables\Columns\TextColumn::make('starts_at')->label('يبدأ')->dateTime(),
                Tables\Columns\TextColumn::make('ends_at')->label('ينتهي')->dateTime(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('network_id')->label('الشبكة')->relationship('network', 'name'),
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
            'index' => Pages\ListDailyOffers::route('/'),
            'create' => Pages\CreateDailyOffer::route('/create'),
            'edit' => Pages\EditDailyOffer::route('/{record}/edit'),
        ];
    }
}
