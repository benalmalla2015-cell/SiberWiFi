<?php

namespace App\Filament\Resources;

use App\Filament\Resources\AdvertisementResource\Pages;
use App\Models\Advertisement;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class AdvertisementResource extends Resource
{
    protected static ?string $model = Advertisement::class;
    protected static ?int $navigationSort = 2;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-megaphone'; }
    public static function getNavigationLabel(): string { return 'الإعلانات'; }
    public static function getNavigationGroup(): ?string { return 'التطبيق'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\TextInput::make('title')->label('العنوان')->nullable()->maxLength(255),
            Forms\Components\FileUpload::make('image')
                ->label('الصورة')
                ->image()
                ->directory('advertisements')
                ->required(),
            Forms\Components\TextInput::make('url')->label('الرابط')->url()->maxLength(255),
            Forms\Components\TextInput::make('position')->label('الموضع')->maxLength(100)->placeholder('الشريط الرئيسي / نافذة منبثقة'),
            Forms\Components\TextInput::make('sort_order')->label('الترتيب')->numeric()->default(0),
            Grid::make(2)->schema([
                Forms\Components\DateTimePicker::make('starts_at')->label('تاريخ البدء'),
                Forms\Components\DateTimePicker::make('ends_at')->label('تاريخ الانتهاء'),
            ]),
            Forms\Components\Toggle::make('is_active')->label('نشط')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('title')->label('العنوان')->searchable(),
                Tables\Columns\ImageColumn::make('image')->label('الصورة')->disk('public'),
                Tables\Columns\TextColumn::make('position')->label('الموضع'),
                Tables\Columns\TextColumn::make('sort_order')->label('الترتيب')->sortable(),
                Tables\Columns\IconColumn::make('is_active')->label('نشط')->boolean(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\TernaryFilter::make('is_active')->label('نشط'),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('sort_order')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListAdvertisements::route('/'),
            'create' => Pages\CreateAdvertisement::route('/create'),
            'edit' => Pages\EditAdvertisement::route('/{record}/edit'),
        ];
    }
}
