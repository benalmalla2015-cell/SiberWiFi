<?php

namespace App\Filament\Resources;

use App\Filament\Resources\MaintenanceModeResource\Pages;
use App\Models\MaintenanceMode;
use Filament\Forms;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class MaintenanceModeResource extends Resource
{
    protected static ?string $model = MaintenanceMode::class;
    protected static ?int $navigationSort = 101;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-wrench-screwdriver'; }
    public static function getNavigationLabel(): string { return 'وضع الصيانة'; }
    public static function getNavigationGroup(): ?string { return 'الإشعارات'; }
    public static function getModelLabel(): string { return 'وضع صيانة'; }
    public static function getPluralModelLabel(): string { return 'أوضاع الصيانة'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Select::make('app')
                ->label('التطبيق')
                ->options([
                    'customer_app'      => 'تطبيق العملاء',
                    'network_owner_app' => 'تطبيق أصحاب الشبكات',
                ])
                ->required()
                ->unique(ignoreRecord: true)
                ->disabledOn('edit'),

            Toggle::make('is_active')
                ->label('تفعيل وضع الصيانة')
                ->default(false)
                ->required()
                ->helperText('عند التفعيل يظهر شاشة الصيانة في التطبيق المحدد'),

            TextInput::make('title')
                ->label('عنوان الرسالة')
                ->required()
                ->default('نحن في وضع الصيانة')
                ->maxLength(255),

            Textarea::make('description')
                ->label('وصف الصيانة')
                ->rows(4)
                ->nullable(),

            FileUpload::make('image')
                ->label('صورة الصيانة')
                ->image()
                ->disk('public')
                ->directory('maintenance_images')
                ->nullable(),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('app')
                    ->label('التطبيق')
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'customer_app'      => 'تطبيق العملاء',
                        'network_owner_app' => 'تطبيق أصحاب الشبكات',
                        default             => $state,
                    }),
                Tables\Columns\IconColumn::make('is_active')
                    ->label('الحالة')
                    ->boolean()
                    ->trueIcon('heroicon-o-check-circle')
                    ->falseIcon('heroicon-o-x-circle')
                    ->trueColor('warning')
                    ->falseColor('success'),
                Tables\Columns\TextColumn::make('title')->label('العنوان'),
                Tables\Columns\ImageColumn::make('image_url')->label('الصورة'),
                Tables\Columns\TextColumn::make('updated_at')->label('آخر تحديث')->dateTime()->sortable(),
            ])
            ->filters([])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('app')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListMaintenanceModes::route('/'),
            'create' => Pages\CreateMaintenanceMode::route('/create'),
            'edit'   => Pages\EditMaintenanceMode::route('/{record}/edit'),
        ];
    }
}
