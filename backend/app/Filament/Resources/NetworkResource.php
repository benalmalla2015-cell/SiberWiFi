<?php

namespace App\Filament\Resources;

use App\Filament\Resources\NetworkResource\Pages;
use App\Models\Network;
use App\Services\NotificationService;
use Filament\Forms;
use Filament\Schemas\Schema;
use Filament\Notifications\Notification;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;

class NetworkResource extends Resource
{
    protected static ?string $model = Network::class;
    protected static ?int $navigationSort = 1;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-wifi'; }
    public static function getNavigationLabel(): string { return 'الشبكات'; }
    public static function getNavigationGroup(): ?string { return 'إدارة الشبكات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            \Filament\Schemas\Components\Section::make('معلومات الشبكة')->schema([
                Forms\Components\TextInput::make('code')->label('رقم الشبكة (ID)')
                    ->disabled()->dehydrated(false)
                    ->suffixAction(
                        \Filament\Actions\Action::make('copyCode')
                            ->icon('heroicon-o-clipboard-document')
                            ->tooltip('نسخ رقم الشبكة')
                            ->action(fn () => null)
                            ->extraAttributes(fn ($record) => [
                                'onclick' => "navigator.clipboard.writeText('" . ($record?->code ?? '') . "')",
                            ])
                    )
                    ->visibleOn('edit'),
                Forms\Components\TextInput::make('name')->label('اسم الشبكة')->required(),
                Forms\Components\TextInput::make('url')->label('رابط الشبكة')->url(),
                Forms\Components\TextInput::make('phone')->label('رقم التواصل'),
                Forms\Components\Select::make('region_id')->label('المحافظة')->relationship('region', 'name'),
                Forms\Components\Select::make('directorate_id')->label('المديرية')->relationship('directorate', 'name'),
                Forms\Components\Textarea::make('description')->label('الوصف')->columnSpanFull(),
            ])->columns(2),
            \Filament\Schemas\Components\Section::make('الإعدادات')->schema([
                Forms\Components\Select::make('status')->label('الحالة')->options([
                    'pending'   => 'قيد المراجعة',
                    'active'    => 'نشطة',
                    'rejected'  => 'مرفوضة',
                    'suspended' => 'موقوفة',
                ])->required(),
                Forms\Components\Textarea::make('rejection_reason')->label('سبب الرفض')->visible(fn($get) => in_array($get('status'), ['rejected', 'suspended'])),
                Forms\Components\TextInput::make('commission_rate')->label('نسبة العمولة %')->numeric()->default(5),
                Forms\Components\Toggle::make('is_featured')->label('مميزة'),
                Forms\Components\Toggle::make('supports_credit')->label('تدعم الكريدت'),
            ])->columns(2),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\ImageColumn::make('logo')->label('الشعار')->circular(),
                Tables\Columns\TextColumn::make('code')->label('رقم الشبكة')->searchable()->copyable()
                    ->copyMessage('تم نسخ رقم الشبكة')->copyMessageDuration(1500)
                    ->badge()->color('info'),
                Tables\Columns\TextColumn::make('name')->label('اسم الشبكة')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('owner.name')->label('المالك')->searchable(),
                Tables\Columns\TextColumn::make('region.type')
                    ->label('المنطقة')
                    ->formatStateUsing(fn($state) => match ($state) {
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                        default => $state,
                    })
                    ->badge()
                    ->color(fn($state) => match ($state) {
                        'north' => 'info',
                        'south' => 'success',
                        default => 'gray',
                    }),
                Tables\Columns\BadgeColumn::make('status')->label('الحالة')->colors([
                    'warning' => 'pending',
                    'success' => 'active',
                    'danger'  => 'rejected',
                    'gray'    => 'suspended',
                ])->formatStateUsing(fn($s) => match($s) {
                    'pending' => 'قيد المراجعة', 'active' => 'نشطة',
                    'rejected' => 'مرفوضة', 'suspended' => 'موقوفة', default => $s,
                }),
                Tables\Columns\TextColumn::make('sales_count')->label('المبيعات')->sortable(),
                Tables\Columns\TextColumn::make('average_rating')->label('التقييم')->suffix('/5'),
                Tables\Columns\IconColumn::make('is_featured')->label('مميزة')->boolean(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ التسجيل')->date()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('status')->label('الحالة')->options([
                    'pending' => 'قيد المراجعة', 'active' => 'نشطة',
                    'rejected' => 'مرفوضة', 'suspended' => 'موقوفة',
                ]),
                Tables\Filters\SelectFilter::make('region_type')
                    ->label('المنطقة')
                    ->options([
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                    ])
                    ->query(function ($query, array $data) {
                        return $query->when($data['value'], fn($q) => $q->whereHas('region', fn($r) => $r->where('type', $data['value'])));
                    }),
                Tables\Filters\TernaryFilter::make('is_featured')->label('المميزة'),
                Tables\Filters\SelectFilter::make('user_id')
                    ->label('صاحب الشبكة')
                    ->relationship('owner', 'name')
                    ->searchable()
                    ->preload(),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\Action::make('approve')
                    ->label('موافقة')
                    ->icon('heroicon-o-check-circle')
                    ->color('success')
                    ->visible(fn($record) => $record->status === 'pending')
                    ->requiresConfirmation()
                    ->action(function ($record) {
                        $record->update([
                            'status'      => 'active',
                            'approved_at' => now(),
                            'approved_by' => auth()->id(),
                        ]);
                        $record->owner?->networkOwnerProfile?->update([
                            'is_approved' => true,
                            'approved_at' => now(),
                            'approved_by' => auth()->id(),
                        ]);
                        $record->owner?->update(['is_active' => true]);
                        try {
                            if ($record->owner) {
                                app(NotificationService::class)->send(
                                    $record->owner,
                                    'تمت الموافقة على شبكتك',
                                    'تمت الموافقة على شبكة "' . $record->name . '" وأصبحت ظاهرة للعملاء.',
                                    ['type' => 'network_approved', 'network_id' => $record->id]
                                );
                            }
                        } catch (\Throwable $e) {
                            \Log::warning('FCM notification failed: ' . $e->getMessage());
                        }
                        Notification::make()->title('تمت الموافقة على الشبكة')->success()->send();
                    }),
                \Filament\Actions\Action::make('reject')
                    ->label('رفض')
                    ->icon('heroicon-o-x-circle')
                    ->color('danger')
                    ->visible(fn($record) => $record->status === 'pending')
                    ->form([Forms\Components\Textarea::make('rejection_reason')->label('سبب الرفض')->required()])
                    ->action(function ($record, array $data) {
                        $record->update(['status' => 'rejected', 'rejection_reason' => $data['rejection_reason']]);
                        try {
                            if ($record->owner) {
                                app(NotificationService::class)->send(
                                    $record->owner,
                                    'تم رفض طلب شبكتك',
                                    'تم رفض شبكة "' . $record->name . '". السبب: ' . $data['rejection_reason'],
                                    ['type' => 'network_rejected', 'network_id' => $record->id]
                                );
                            }
                        } catch (\Throwable $e) {
                            \Log::warning('FCM notification failed: ' . $e->getMessage());
                        }
                        Notification::make()->title('تم رفض الشبكة')->warning()->send();
                    }),
            ])
            ->defaultSort('created_at', 'desc')
            ->poll('10s');
    }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListNetworks::route('/'),
            'create' => Pages\CreateNetwork::route('/create'),
            'edit'   => Pages\EditNetwork::route('/{record}/edit'),
        ];
    }

    public static function getNavigationBadge(): ?string
    {
        try {
            return static::getModel()::where('status', 'pending')->count() ?: null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    public static function getNavigationBadgeColor(): ?string { return 'warning'; }
}
