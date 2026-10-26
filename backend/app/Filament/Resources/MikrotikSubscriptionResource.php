<?php

namespace App\Filament\Resources;

use App\Filament\Resources\MikrotikSubscriptionResource\Pages;
use App\Models\MikrotikSubscription;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class MikrotikSubscriptionResource extends Resource
{
    protected static ?string $model = MikrotikSubscription::class;
    protected static ?int $navigationSort = 13;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-check-badge'; }
    public static function getNavigationLabel(): string { return 'اشتراكات MikroTik'; }
    public static function getNavigationGroup(): ?string { return 'الشبكات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Grid::make(2)->schema([
                Forms\Components\Select::make('user_id')
                    ->label('المالك')
                    ->relationship('user', 'name')
                    ->searchable()
                    ->required(),
                Forms\Components\Select::make('plan_id')
                    ->label('الخطة (فارغ = تجربة)')
                    ->relationship('plan', 'name')
                    ->searchable()
                    ->nullable(),
            ]),
            Grid::make(3)->schema([
                Forms\Components\Select::make('status')
                    ->label('الحالة')
                    ->options([
                        'trial' => 'تجربة',
                        'active' => 'نشط',
                        'expired' => 'منتهٍ',
                        'cancelled' => 'ملغى',
                    ])
                    ->required(),
                Forms\Components\DateTimePicker::make('starts_at')
                    ->label('البداية'),
                Forms\Components\DateTimePicker::make('ends_at')
                    ->label('النهاية'),
            ]),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('user.name')->label('المالك')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('plan.name')->label('الخطة')->placeholder('تجربة'),
                Tables\Columns\TextColumn::make('status')->label('الحالة')
                    ->badge()
                    ->formatStateUsing(fn($s) => match ($s) {
                        'trial' => 'تجربة',
                        'active' => 'نشط',
                        'expired' => 'منتهٍ',
                        'cancelled' => 'ملغى',
                        default => $s,
                    })
                    ->color(fn($s) => match ($s) {
                        'active' => 'success',
                        'trial' => 'info',
                        'expired' => 'danger',
                        default => 'gray',
                    }),
                Tables\Columns\TextColumn::make('ends_at')->label('تنتهي في')->dateTime()->sortable(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('status')
                    ->label('الحالة')
                    ->options([
                        'trial' => 'تجربة',
                        'active' => 'نشط',
                        'expired' => 'منتهٍ',
                        'cancelled' => 'ملغى',
                    ]),
                Tables\Filters\SelectFilter::make('user_id')
                    ->label('المالك')
                    ->relationship('user', 'name')
                    ->searchable(),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListMikrotikSubscriptions::route('/'),
            'edit' => Pages\EditMikrotikSubscription::route('/{record}/edit'),
        ];
    }
}
