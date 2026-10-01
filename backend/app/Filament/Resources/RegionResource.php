<?php

namespace App\Filament\Resources;

use App\Filament\Resources\RegionResource\Pages;
use App\Models\Region;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class RegionResource extends Resource
{
    protected static ?string $model = Region::class;
    protected static ?int $navigationSort = 10;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-map'; }
    public static function getNavigationLabel(): string { return 'المناطق والمديريات'; }
    public static function getNavigationGroup(): ?string { return 'إعدادات النظام'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            \Filament\Schemas\Components\Section::make()->schema([
                Forms\Components\TextInput::make('name')->label('اسم المنطقة (عربي)')->required(),
                Forms\Components\TextInput::make('name_en')->label('اسم المنطقة (إنجليزي)'),
                Forms\Components\Select::make('type')->label('النوع')->options([
                    'north' => 'شمال اليمن',
                    'south' => 'جنوب اليمن',
                ])->required(),
                Forms\Components\Select::make('currency')->label('العملة')->options([
                    'YER_OLD' => 'ريال يمني قديم (شمال)',
                    'YER_NEW' => 'ريال يمني (جنوب)',
                ])->required(),
                Forms\Components\Toggle::make('is_active')->label('نشطة')->default(true),
            ])->columns(2),
            \Filament\Schemas\Components\Section::make('المديريات')->schema([
                Forms\Components\Repeater::make('directorates')
                    ->relationship()
                    ->schema([
                        Forms\Components\TextInput::make('name')->label('اسم المديرية (عربي)')->required(),
                        Forms\Components\TextInput::make('name_en')->label('اسم المديرية (إنجليزي)'),
                        Forms\Components\Toggle::make('is_active')->label('نشطة')->default(true)->inline(),
                    ])
                    ->columns(3)
                    ->label('')
                    ->addActionLabel('إضافة مديرية'),
            ]),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('name')->label('المنطقة')->searchable()->sortable(),
                Tables\Columns\BadgeColumn::make('type')->label('النوع')->formatStateUsing(fn($s) => $s === 'north' ? 'شمال' : 'جنوب')->colors(['primary' => 'north', 'success' => 'south']),
                Tables\Columns\TextColumn::make('currency')->label('العملة'),
                Tables\Columns\TextColumn::make('directorates_count')->label('المديريات')->counts('directorates'),
                Tables\Columns\IconColumn::make('is_active')->label('نشطة')->boolean(),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
            ]);
    }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListRegions::route('/'),
            'create' => Pages\CreateRegion::route('/create'),
            'edit'   => Pages\EditRegion::route('/{record}/edit'),
        ];
    }
}
