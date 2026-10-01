<?php

namespace App\Filament\Resources;

use App\Filament\Resources\AppSettingResource\Pages;
use App\Models\AppSetting;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class AppSettingResource extends Resource
{
    protected static ?string $model = AppSetting::class;
    protected static ?int $navigationSort = 1;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-cog-6-tooth'; }
    public static function getNavigationLabel(): string { return 'إعدادات التطبيق'; }
    public static function getNavigationGroup(): ?string { return 'الإعدادات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\TextInput::make('key')->label('المفتاح')->required()->unique(ignoreRecord: true)->maxLength(255),
            Forms\Components\TextInput::make('group')->label('المجموعة')->maxLength(100),
            Forms\Components\Select::make('type')
                ->label('نوع القيمة')
                ->options([
                    'string' => 'نص',
                    'integer' => 'عدد صحيح',
                    'float' => 'عدد عشري',
                    'boolean' => 'نعم/لا',
                    'json' => 'JSON',
                ])
                ->required()
                ->default('string'),
            Forms\Components\Textarea::make('value')->label('القيمة')->rows(4),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('key')->label('المفتاح')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('group')->label('المجموعة')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('type')->label('النوع'),
                Tables\Columns\TextColumn::make('value')->label('القيمة')->limit(50),
                Tables\Columns\TextColumn::make('updated_at')->label('آخر تحديث')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('type')->label('النوع')->options([
                    'string' => 'نص',
                    'integer' => 'عدد صحيح',
                    'float' => 'عدد عشري',
                    'boolean' => 'نعم/لا',
                    'json' => 'JSON',
                ]),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('key')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListAppSettings::route('/'),
            'create' => Pages\CreateAppSetting::route('/create'),
            'edit' => Pages\EditAppSetting::route('/{record}/edit'),
        ];
    }
}
