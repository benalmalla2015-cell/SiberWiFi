<?php

namespace App\Filament\Resources;

use App\Filament\Resources\CardCategoryResource\Pages;
use App\Models\CardCategory;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class CardCategoryResource extends Resource
{
    protected static ?string $model = CardCategory::class;
    protected static ?int $navigationSort = 1;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-squares-2x2'; }
    public static function getNavigationLabel(): string { return 'فئات الكروت'; }
    public static function getNavigationGroup(): ?string { return 'الكروت'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\Select::make('network_id')
                ->label('الشبكة')
                ->relationship('network', 'name')
                ->searchable()
                ->required(),
            Forms\Components\TextInput::make('name')->label('اسم الفئة')->required()->maxLength(255),
            Forms\Components\TextInput::make('speed')->label('السرعة')->maxLength(100),
            Grid::make(2)->schema([
                Forms\Components\TextInput::make('duration')->label('المدة')->numeric()->minValue(1),
                Forms\Components\TextInput::make('duration_unit')->label('وحدة المدة')->maxLength(50)->placeholder('يوم / أسبوع / شهر'),
            ]),
            Grid::make(2)->schema([
                Forms\Components\TextInput::make('price')->label('سعر البيع')->required()->numeric()->prefix('ر.ي'),
                Forms\Components\TextInput::make('value')->label('قيمة الكرت')->required()->numeric()->prefix('ر.ي'),
            ]),
            Forms\Components\Textarea::make('description')->label('الوصف')->rows(3),
            Forms\Components\Toggle::make('is_active')->label('نشطة')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('network.name')->label('الشبكة')->searchable(),
                Tables\Columns\TextColumn::make('name')->label('الفئة')->searchable(),
                Tables\Columns\TextColumn::make('speed')->label('السرعة'),
                Tables\Columns\TextColumn::make('duration')->label('المدة')->formatStateUsing(fn($s, $r) => $s ? "$s {$r->duration_unit}" : '-'),
                Tables\Columns\TextColumn::make('price')->label('السعر')->money('YER')->sortable(),
                Tables\Columns\TextColumn::make('value')->label('القيمة')->money('YER'),
                Tables\Columns\IconColumn::make('is_active')->label('نشطة')->boolean(),
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
            'index' => Pages\ListCardCategories::route('/'),
            'create' => Pages\CreateCardCategory::route('/create'),
            'edit' => Pages\EditCardCategory::route('/{record}/edit'),
        ];
    }
}
