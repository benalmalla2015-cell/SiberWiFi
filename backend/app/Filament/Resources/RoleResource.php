<?php

namespace App\Filament\Resources;

use App\Filament\Resources\RoleResource\Pages;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;
use Spatie\Permission\Models\Role;

class RoleResource extends Resource
{
    protected static ?string $model = Role::class;
    protected static ?int $navigationSort = 3;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-shield-check'; }
    public static function getNavigationLabel(): string { return 'الأدوار'; }
    public static function getNavigationGroup(): ?string { return 'إدارة المستخدمين'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Section::make()->schema([
                Forms\Components\TextInput::make('name')
                    ->label('اسم الدور')
                    ->required()
                    ->unique(ignoreRecord: true)
                    ->maxLength(255),
                Forms\Components\TextInput::make('guard_name')
                    ->label('الحارس (Guard)')
                    ->default('web')
                    ->required()
                    ->maxLength(255),
                Forms\Components\CheckboxList::make('permissions')
                    ->label('الصلاحيات')
                    ->relationship('permissions', 'name')
                    ->getOptionLabelFromRecordUsing(fn ($record) => PermissionResource::formatPermissionName($record->name))
                    ->searchable()
                    ->columns(3),
            ])->columns(2),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#')->sortable(),
                Tables\Columns\TextColumn::make('name')->label('اسم الدور')->searchable(),
                Tables\Columns\TextColumn::make('guard_name')->label('الحارس')->badge(),
                Tables\Columns\TextColumn::make('permissions_count')
                    ->label('عدد الصلاحيات')
                    ->counts('permissions'),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->date()->sortable(),
            ])
            ->filters([])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('created_at', 'desc');
    }

    public static function getRelations(): array
    {
        return [];
    }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListRoles::route('/'),
            'create' => Pages\CreateRole::route('/create'),
            'edit'   => Pages\EditRole::route('/{record}/edit'),
        ];
    }
}
