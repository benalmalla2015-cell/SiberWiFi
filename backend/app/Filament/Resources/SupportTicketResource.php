<?php

namespace App\Filament\Resources;

use App\Filament\Resources\SupportTicketResource\Pages;
use App\Models\SupportTicket;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class SupportTicketResource extends Resource
{
    protected static ?string $model = SupportTicket::class;
    protected static ?int $navigationSort = 40;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-ticket'; }
    public static function getNavigationLabel(): string { return 'طلبات الدعم الفني'; }
    public static function getNavigationGroup(): ?string { return 'إدارة المستخدمين'; }
    public static function getPluralModelLabel(): string { return 'طلبات الدعم'; }
    public static function getModelLabel(): string { return 'طلب دعم'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Grid::make(2)->schema([
                Forms\Components\TextInput::make('user.name')
                    ->label('العميل')
                    ->disabled(),
                Forms\Components\Select::make('status')
                    ->label('الحالة')
                    ->options([
                        'open' => 'مفتوح',
                        'in_progress' => 'قيد المعالجة',
                        'closed' => 'مغلق',
                    ])
                    ->required(),
            ]),
            Forms\Components\TextInput::make('subject')
                ->label('الموضوع')
                ->disabled(),
            Forms\Components\Textarea::make('message')
                ->label('رسالة العميل')
                ->disabled()
                ->rows(4),
            Forms\Components\Textarea::make('reply')
                ->label('الرد')
                ->rows(4),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#')->sortable(),
                Tables\Columns\TextColumn::make('user.name')->label('العميل')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('user.phone')->label('رقم الجوال')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('subject')->label('الموضوع')->searchable()->limit(50),
                Tables\Columns\TextColumn::make('message')->label('الرسالة')->limit(60),
                Tables\Columns\TextColumn::make('status')
                    ->label('الحالة')
                    ->badge()
                    ->formatStateUsing(fn (string $state): string => match ($state) {
                        'open' => 'مفتوح',
                        'in_progress' => 'قيد المعالجة',
                        'closed' => 'مغلق',
                        default => $state,
                    })
                    ->color(fn (string $state): string => match ($state) {
                        'open' => 'danger',
                        'in_progress' => 'warning',
                        'closed' => 'success',
                        default => 'gray',
                    }),
                Tables\Columns\TextColumn::make('repliedBy.name')->label('تم الرد بواسطة'),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('status')
                    ->label('الحالة')
                    ->options([
                        'open' => 'مفتوح',
                        'in_progress' => 'قيد المعالجة',
                        'closed' => 'مغلق',
                    ]),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('رد / تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListSupportTickets::route('/'),
            'edit' => Pages\EditSupportTicket::route('/{record}/edit'),
        ];
    }
}
