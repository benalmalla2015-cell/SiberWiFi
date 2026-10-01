<?php

namespace App\Filament\Resources;

use App\Filament\Resources\AdvanceCategorySettingResource\Pages;
use App\Models\AdvanceCategorySetting;
use App\Services\NotificationService;
use Filament\Forms;
use Filament\Notifications\Notification;
use Filament\Schemas\Schema;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;

/**
 * Network owners request "سلفني" (advance) support per card category —
 * which categories, and how many cards may be given out as an advance.
 * The request only becomes active/visible to customers after an admin
 * approves it here.
 */
class AdvanceCategorySettingResource extends Resource
{
    protected static ?string $model = AdvanceCategorySetting::class;
    protected static ?int $navigationSort = 2;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-hand-raised'; }
    public static function getNavigationLabel(): string { return 'طلبات تفعيل السلفة'; }
    public static function getNavigationGroup(): ?string { return 'إدارة الشبكات'; }

    public static function form(Schema $schema): Schema { return $schema->components([]); }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('network.name')->label('الشبكة')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('network.owner.name')->label('صاحب الشبكة')->searchable(),
                Tables\Columns\TextColumn::make('name')->label('الفئة')->searchable(),
                Tables\Columns\TextColumn::make('price')->label('سعر الفئة')->money('YER'),
                Tables\Columns\TextColumn::make('advance_max_cards')->label('الحد الأقصى للكروت'),
                Tables\Columns\TextColumn::make('advance_max_per_customer')->label('الحد لكل عميل')->formatStateUsing(fn($s) => $s ?? 'بدون حد'),
                Tables\Columns\TextColumn::make('advance_used_count')->label('المستخدم حالياً'),
                Tables\Columns\BadgeColumn::make('advance_status')->label('الحالة')->colors([
                    'warning' => 'pending',
                    'success' => 'approved',
                    'danger' => 'rejected',
                ])->formatStateUsing(fn($s) => match ($s) {
                    'pending' => 'قيد المراجعة',
                    'approved' => 'موافَق عليها',
                    'rejected' => 'مرفوضة',
                    default => $s,
                }),
                Tables\Columns\TextColumn::make('advance_requested_at')->label('تاريخ الطلب')->dateTime('Y-m-d H:i')->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('advance_status')->label('الحالة')->options([
                    'pending' => 'قيد المراجعة',
                    'approved' => 'موافَق عليها',
                    'rejected' => 'مرفوضة',
                ]),
            ])
            ->actions([
                \Filament\Actions\Action::make('approve')
                    ->label('موافقة')
                    ->icon('heroicon-o-check-circle')
                    ->color('success')
                    ->requiresConfirmation()
                    ->visible(fn(AdvanceCategorySetting $record) => $record->advance_status === 'pending')
                    ->action(function (AdvanceCategorySetting $record) {
                        $record->update([
                            'advance_status' => 'approved',
                            'advance_approved_at' => now(),
                            'advance_approved_by' => auth()->id(),
                            'advance_rejection_reason' => null,
                        ]);
                        $record->network?->recalculateAdvanceSupport();
                        try {
                            if ($record->network?->owner) {
                                app(NotificationService::class)->send(
                                    $record->network->owner,
                                    'تمت الموافقة على تفعيل السلفة',
                                    'تمت الموافقة على تفعيل خدمة السلفة لفئة "' . $record->name . '" بحد أقصى ' . $record->advance_max_cards . ' كرت.',
                                    ['type' => 'advance_approved', 'category_id' => $record->id]
                                );
                            }
                        } catch (\Throwable $e) {
                            \Log::warning('Advance approval notification failed: ' . $e->getMessage());
                        }
                        Notification::make()->title('تمت الموافقة على طلب السلفة')->success()->send();
                    }),
                \Filament\Actions\Action::make('reject')
                    ->label('رفض')
                    ->icon('heroicon-o-x-circle')
                    ->color('danger')
                    ->requiresConfirmation()
                    ->visible(fn(AdvanceCategorySetting $record) => $record->advance_status === 'pending')
                    ->form([Forms\Components\Textarea::make('reason')->label('سبب الرفض')->required()])
                    ->action(function (AdvanceCategorySetting $record, array $data) {
                        $record->update([
                            'advance_status' => 'rejected',
                            'advance_rejection_reason' => $data['reason'],
                        ]);
                        $record->network?->recalculateAdvanceSupport();
                        try {
                            if ($record->network?->owner) {
                                app(NotificationService::class)->send(
                                    $record->network->owner,
                                    'تم رفض طلب تفعيل السلفة',
                                    'تم رفض طلب تفعيل خدمة السلفة لفئة "' . $record->name . '". السبب: ' . $data['reason'],
                                    ['type' => 'advance_rejected', 'category_id' => $record->id]
                                );
                            }
                        } catch (\Throwable $e) {
                            \Log::warning('Advance rejection notification failed: ' . $e->getMessage());
                        }
                        Notification::make()->title('تم رفض طلب السلفة')->warning()->send();
                    }),
                \Filament\Actions\Action::make('disable')
                    ->label('إيقاف')
                    ->icon('heroicon-o-pause-circle')
                    ->color('gray')
                    ->requiresConfirmation()
                    ->visible(fn(AdvanceCategorySetting $record) => $record->advance_status === 'approved')
                    ->action(function (AdvanceCategorySetting $record) {
                        $record->update(['advance_enabled' => false, 'advance_status' => 'none']);
                        $record->network?->recalculateAdvanceSupport();
                        Notification::make()->title('تم إيقاف خدمة السلفة لهذه الفئة')->success()->send();
                    }),
            ])
            ->defaultSort('advance_requested_at', 'desc')
            ->paginated([25, 50, 100]);
    }

    public static function canCreate(): bool { return false; }

    public static function getPages(): array
    {
        return ['index' => Pages\ListAdvanceCategorySettings::route('/')];
    }

    public static function getNavigationBadge(): ?string
    {
        try {
            return static::getModel()::where('advance_status', 'pending')->count() ?: null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    public static function getNavigationBadgeColor(): ?string { return 'warning'; }
}
