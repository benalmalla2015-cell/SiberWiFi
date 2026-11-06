<?php

namespace App\Filament\Resources;

use App\Filament\Resources\AccSubscriptionResource\Pages;
use App\Models\AccSubscription;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

/**
 * Tenant-keyed accounting subscriptions — one row covers the owner
 * plus every enrolled agent (see AccBillingController).
 */
class AccSubscriptionResource extends Resource
{
    protected static ?string $model = AccSubscription::class;
    protected static ?int $navigationSort = 16;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-check-badge'; }
    public static function getNavigationLabel(): string { return 'اشتراكات المحاسبة'; }
    public static function getNavigationGroup(): ?string { return 'المحاسبة'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Grid::make(2)->schema([
                Forms\Components\Select::make('network_owner_id')
                    ->label('المالك')
                    ->relationship('owner', 'name')
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
            Forms\Components\CheckboxList::make('granted_features')
                ->label('ميزات إضافية لهذا الحساب')
                ->options(AccPlanResource::featureLabels())
                ->columns(3)
                ->helperText('تُفتح لهذا المالك ووكلائه حتى لو لم تكن في خطته'),
            Forms\Components\CheckboxList::make('revoked_features')
                ->label('ميزات محظورة على هذا الحساب')
                ->options(AccPlanResource::featureLabels())
                ->columns(3)
                ->helperText('تُحجب عن هذا المالك ووكلائه حتى لو اشتراكه نشط'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('owner.name')->label('المالك')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('plan.name')->label('الخطة')->placeholder('تجربة'),
                Tables\Columns\TextColumn::make('status')->label('الحالة')
                    ->badge()
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'trial' => 'تجربة',
                        'active' => 'نشط',
                        'expired' => 'منتهٍ',
                        'cancelled' => 'ملغى',
                        default => $state,
                    })
                    ->color(fn ($state) => match ($state) {
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
                Tables\Filters\SelectFilter::make('network_owner_id')
                    ->label('المالك')
                    ->relationship('owner', 'name')
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
            'index' => Pages\ListAccSubscriptions::route('/'),
            'create' => Pages\CreateAccSubscription::route('/create'),
            'edit' => Pages\EditAccSubscription::route('/{record}/edit'),
        ];
    }
}
