<?php

namespace App\Filament\Resources;

use App\Filament\Resources\MikrotikRouterResource\Pages;
use App\Models\MikrotikRouter;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class MikrotikRouterResource extends Resource
{
    protected static ?string $model = MikrotikRouter::class;
    protected static ?int $navigationSort = 11;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-server-stack'; }
    public static function getNavigationLabel(): string { return 'رواتر MikroTik'; }
    public static function getNavigationGroup(): ?string { return 'الشبكات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Grid::make(2)->schema([
                Forms\Components\Select::make('user_id')
                    ->label('مالك الراوتر')
                    ->relationship('owner', 'name')
                    ->searchable()
                    ->required(),
                Forms\Components\Select::make('network_id')
                    ->label('الشبكة المرتبطة')
                    ->relationship('network', 'name')
                    ->searchable()
                    ->nullable(),
            ]),
            Grid::make(3)->schema([
                Forms\Components\TextInput::make('name')
                    ->label('الاسم')
                    ->maxLength(255),
                Forms\Components\TextInput::make('host')
                    ->label('العنوان')
                    ->required()
                    ->maxLength(255),
                Forms\Components\TextInput::make('api_port')
                    ->label('منفذ API')
                    ->numeric()
                    ->default(8728),
            ]),
            Grid::make(3)->schema([
                Forms\Components\TextInput::make('identity')
                    ->label('هوية الراوتر')
                    ->maxLength(255),
                Forms\Components\TextInput::make('board_name')
                    ->label('اللوحة')
                    ->maxLength(255),
                Forms\Components\TextInput::make('os_version')
                    ->label('إصدار RouterOS')
                    ->maxLength(255),
            ]),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('owner.name')->label('المالك')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('display_name')->label('الاسم')
                    ->getStateUsing(fn ($record) => $record->name ?: $record->identity ?: '—')
                    ->searchable(['name', 'identity']),
                Tables\Columns\TextColumn::make('endpoint')->label('العنوان')
                    ->getStateUsing(fn ($record) => "{$record->host}:{$record->api_port}")
                    ->searchable(['host']),
                Tables\Columns\TextColumn::make('network.name')->label('الشبكة')->sortable()->placeholder('—'),
                Tables\Columns\TextColumn::make('board_name')->label('اللوحة')->placeholder('—'),
                Tables\Columns\TextColumn::make('os_version')->label('الإصدار')->placeholder('—'),
                Tables\Columns\TextColumn::make('hotspot_users_count')->label('المستخدمون')->sortable(),
                Tables\Columns\TextColumn::make('last_seen_at')->label('آخر ظهور')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('user_id')
                    ->label('المالك')
                    ->relationship('owner', 'name'),
                Tables\Filters\Filter::make('online')
                    ->label('نشط خلال 24 ساعة')
                    ->query(fn ($query) => $query->where('last_seen_at', '>=', now()->subDay())),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('last_seen_at', 'desc')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListMikrotikRouters::route('/'),
            'edit' => Pages\EditMikrotikRouter::route('/{record}/edit'),
        ];
    }
}
