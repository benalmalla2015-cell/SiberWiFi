<?php

namespace App\Filament\Resources;

use App\Filament\Resources\BankAccountResource\Pages;
use App\Models\BankAccount;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class BankAccountResource extends Resource
{
    protected static ?string $model = BankAccount::class;
    protected static ?int $navigationSort = 3;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-building-library'; }
    public static function getNavigationLabel(): string { return 'الحسابات المصرفية'; }
    public static function getNavigationGroup(): ?string { return 'المالية'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Grid::make(2)->schema([
                Forms\Components\TextInput::make('owner_name')
                    ->label('اسم صاحب الحساب')
                    ->required()
                    ->maxLength(255),
                Forms\Components\TextInput::make('bank_name')
                    ->label('اسم الحساب المصرفي / البنك')
                    ->required()
                    ->maxLength(255),
            ]),
            Grid::make(2)->schema([
                Forms\Components\TextInput::make('account_number')
                    ->label('رقم الحساب')
                    ->required()
                    ->maxLength(100),
                Forms\Components\TextInput::make('sort_order')
                    ->label('الترتيب')
                    ->numeric()
                    ->default(0),
            ]),
            Forms\Components\Toggle::make('is_active')
                ->label('نشط')
                ->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('owner_name')->label('اسم صاحب الحساب')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('bank_name')->label('اسم الحساب المصرفي')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('account_number')->label('رقم الحساب')->searchable()->copyable(),
                Tables\Columns\IconColumn::make('is_active')->label('نشط')->boolean(),
                Tables\Columns\TextColumn::make('sort_order')->label('الترتيب')->sortable(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\TernaryFilter::make('is_active')->label('نشط'),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('sort_order', 'asc')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListBankAccounts::route('/'),
            'create' => Pages\CreateBankAccount::route('/create'),
            'edit' => Pages\EditBankAccount::route('/{record}/edit'),
        ];
    }
}
