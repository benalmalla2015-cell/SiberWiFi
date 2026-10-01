<?php

namespace App\Filament\Resources;

use App\Exports\UsersExport;
use App\Filament\Resources\PermissionResource;
use App\Filament\Resources\UserResource\Pages;
use App\Models\User;
use App\Models\WalletLog;
use Filament\Forms;
use Filament\Notifications\Notification;
use Filament\Schemas\Schema;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;
use Maatwebsite\Excel\Facades\Excel;
use Illuminate\Support\Facades\DB;

class UserResource extends Resource
{
    protected static ?string $model = User::class;
    protected static ?int $navigationSort = 1;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-users'; }
    public static function getNavigationLabel(): string { return 'المستخدمون'; }
    public static function getNavigationGroup(): ?string { return 'إدارة المستخدمين'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            \Filament\Schemas\Components\Section::make()->schema([
                Forms\Components\TextInput::make('name')->label('الاسم')->required(),
                Forms\Components\TextInput::make('phone')->label('رقم الهاتف')->required()->unique(ignoreRecord: true),
                Forms\Components\TextInput::make('email')->label('البريد الإلكتروني')->email()->unique(ignoreRecord: true),
                Forms\Components\Select::make('type')->label('نوع الحساب')->options([
                    'client'         => 'عميل',
                    'network_owner'  => 'صاحب شبكة',
                    'charging_point' => 'نقطة شحن',
                    'admin'          => 'مشرف',
                ])->required(),
                Forms\Components\Select::make('region_type')->label('المنطقة')->options([
                    'north' => 'الشمال (ريال يمني قديم)',
                    'south' => 'الجنوب (ريال يمني)',
                ])->required(),
                Forms\Components\TextInput::make('password')->label('كلمة المرور')->password()
                    // Let the User model's "hashed" cast hash the plain password once.
                    // NOTE: the injected value must be named $state — Filament
                    // resolves closure params by name; any other name makes the
                    // field silently non-dehydrated and the password never saves.
                    ->dehydrateStateUsing(fn($state) => filled($state) ? $state : null)
                    ->dehydrated(fn($state) => filled($state))
                    ->required(fn(string $operation): bool => $operation === 'create')
                    ->minLength(6),
                Forms\Components\Toggle::make('is_active')->label('نشط')->default(true),
                Forms\Components\Toggle::make('is_verified')->label('موثق'),
            ])->columns(2),
            \Filament\Schemas\Components\Section::make('الأدوار والصلاحيات')->schema([
                Forms\Components\Select::make('roles')->multiple()->relationship('roles', 'name')->preload()->label('الأدوار'),
                Forms\Components\Select::make('permissions')->multiple()->relationship('permissions', 'name')->preload()->label('الصلاحيات المباشرة')
                    ->getOptionLabelFromRecordUsing(fn ($record) => PermissionResource::formatPermissionName($record->name)),
            ])->columns(2),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#')->sortable(),
                Tables\Columns\TextColumn::make('name')->label('الاسم')->searchable(),
                Tables\Columns\TextColumn::make('phone')->label('الهاتف')->searchable(),
                Tables\Columns\BadgeColumn::make('type')->label('النوع')->colors([
                    'primary' => 'client',
                    'success' => 'network_owner',
                    'warning' => 'charging_point',
                    'danger'  => 'admin',
                ])->formatStateUsing(fn($state) => match($state) {
                    'client' => 'عميل', 'network_owner' => 'صاحب شبكة',
                    'charging_point' => 'نقطة شحن', 'admin' => 'مشرف', default => $state,
                }),
                Tables\Columns\BadgeColumn::make('region_type')->label('المنطقة')->colors([
                    'info'  => 'north',
                    'warning' => 'south',
                ])->formatStateUsing(fn($state) => match($state) {
                    'north' => 'الشمال',
                    'south' => 'الجنوب',
                    default => $state,
                }),
                Tables\Columns\TextColumn::make('balance')->label('الرصيد')->suffix(' ر.ي')->sortable(),
                Tables\Columns\IconColumn::make('is_active')->label('نشط')->boolean(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ التسجيل')->date()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('type')->label('النوع')->options([
                    'client' => 'عميل', 'network_owner' => 'صاحب شبكة',
                    'charging_point' => 'نقطة شحن', 'admin' => 'مشرف',
                ]),
                Tables\Filters\SelectFilter::make('region_type')
                    ->label('المنطقة')
                    ->options([
                        'north' => 'الشمال (ريال يمني قديم)',
                        'south' => 'الجنوب (ريال يمني)',
                    ]),
                Tables\Filters\TernaryFilter::make('is_active')->label('الحالة'),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\Action::make('toggle_active')
                    ->label(fn($record) => $record?->is_active ? 'إيقاف' : 'تفعيل')
                    ->icon(fn($record) => $record?->is_active ? 'heroicon-o-x-circle' : 'heroicon-o-check-circle')
                    ->color(fn($record) => $record?->is_active ? 'danger' : 'success')
                    ->action(function ($record) {
                        $newActive = ! $record->is_active;
                        $record->update(['is_active' => $newActive]);

                        $notifier = app(\App\Services\NotificationService::class);

                        if (! $newActive) {
                            // Keep the Sanctum token: the `active` middleware answers
                            // every API call with 403 account_suspended, so the app can
                            // still detect the suspension even if the FCM push is missed.
                            try {
                                $notifier->send(
                                    $record,
                                    'تم إيقاف الحساب',
                                    'تم إيقاف الحساب من قبل إدارة التطبيق يرجى مراجعة الدعم الفني',
                                    ['type' => 'account_suspended']
                                );
                            } catch (\Throwable $e) {
                                \Log::warning('FCM suspend notification failed: ' . $e->getMessage());
                            }

                            Notification::make()
                                ->title('تم إيقاف الحساب')
                                ->success()
                                ->send();
                        } else {
                            try {
                                $notifier->send(
                                    $record,
                                    'تم تفعيل الحساب',
                                    'تم تفعيل حسابك من قبل إدارة التطبيق.',
                                    ['type' => 'account_activated']
                                );
                            } catch (\Throwable $e) {
                                \Log::warning('FCM activate notification failed: ' . $e->getMessage());
                            }

                            Notification::make()
                                ->title('تم تفعيل الحساب')
                                ->success()
                                ->send();
                        }
                    }),
                \Filament\Actions\Action::make('charge_balance')
                    ->label('شحن رصيد')
                    ->icon('heroicon-o-plus-circle')
                    ->color('success')
                    ->form([
                        Forms\Components\TextInput::make('amount')->label('المبلغ')->numeric()->minValue(1)->required(),
                        Forms\Components\TextInput::make('note')->label('ملاحظة / سبب الشحن')->required(),
                    ])
                    ->action(function ($record, array $data) {
                        DB::transaction(function () use ($record, $data) {
                            $user = User::lockForUpdate()->findOrFail($record->id);
                            $before = (float) $user->balance;
                            $user->increment('balance', $data['amount']);
                            $user->increment('available_balance', $data['amount']);
                            $user->refresh();
                            WalletLog::create([
                                'user_id'        => $user->id,
                                'type'           => 'credit',
                                'amount'         => $data['amount'],
                                'balance_before' => $before,
                                'balance_after'  => $user->balance,
                                'description'    => 'شحن يدوي من الإدارة: ' . $data['note'],
                                'reference_type' => 'manual',
                            ]);
                        });
                        $record->refresh();
                        try {
                            app(\App\Services\NotificationService::class)->send(
                                $record,
                                'تم شحن رصيدك',
                                'تم إضافة ' . number_format($data['amount'], 0) . ' ريال إلى رصيدك. رصيدك الحالي: ' . number_format($record->balance, 0) . ' ريال.',
                                ['type' => 'wallet_topup', 'amount' => $data['amount']]
                            );
                        } catch (\Throwable $e) {
                            \Log::warning('FCM send failed: ' . $e->getMessage());
                        }
                        Notification::make()->title('تم شحن ' . number_format($data['amount']) . ' ريال لحساب ' . $record->name)->success()->send();
                    }),
                \Filament\Actions\Action::make('deduct_balance')
                    ->label('خصم رصيد')
                    ->icon('heroicon-o-minus-circle')
                    ->color('danger')
                    ->form([
                        Forms\Components\TextInput::make('amount')->label('المبلغ')->numeric()->minValue(1)->required(),
                        Forms\Components\TextInput::make('note')->label('ملاحظة / سبب الخصم')->required(),
                    ])
                    ->action(function ($record, array $data) {
                        $deducted = DB::transaction(function () use ($record, $data) {
                            $user = User::lockForUpdate()->findOrFail($record->id);
                            if ((float) $user->balance < (float) $data['amount'] || (float) $user->available_balance < (float) $data['amount']) {
                                return false;
                            }
                            $before = (float) $user->balance;
                            $user->decrement('balance', $data['amount']);
                            $user->decrement('available_balance', $data['amount']);
                            $user->refresh();
                            WalletLog::create([
                                'user_id' => $user->id,
                                'type' => 'debit',
                                'amount' => $data['amount'],
                                'balance_before' => $before,
                                'balance_after' => $user->balance,
                                'description' => 'خصم يدوي من الإدارة: ' . $data['note'],
                                'reference_type' => 'manual',
                            ]);
                            return true;
                        });
                        if (!$deducted) {
                            Notification::make()->title('رصيد غير كافٍ للخصم')->danger()->send();
                            return;
                        }
                        $record->refresh();
                        try {
                            app(\App\Services\NotificationService::class)->send(
                                $record,
                                'تم خصم من رصيدك',
                                'تم خصم ' . number_format($data['amount'], 0) . ' ريال من رصيدك. السبب: ' . $data['note'],
                                ['type' => 'wallet_deduction', 'amount' => $data['amount']]
                            );
                        } catch (\Throwable $e) {
                            \Log::warning('FCM send failed: ' . $e->getMessage());
                        }
                        Notification::make()->title('تم خصم ' . number_format($data['amount']) . ' ريال من حساب ' . $record->name)->warning()->send();
                    }),
            ])
            ->headerActions([
                \Filament\Actions\Action::make('export')
                    ->label('تصدير Excel')
                    ->icon('heroicon-o-arrow-down-tray')
                    ->color('success')
                    ->action(fn() => Excel::download(new UsersExport(), 'users-' . now()->format('Y-m-d') . '.xlsx')),
            ])
            ->defaultSort('created_at', 'desc')
            ->poll('10s');
    }

    public static function getRelations(): array { return []; }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListUsers::route('/'),
            'create' => Pages\CreateUser::route('/create'),
            'edit'   => Pages\EditUser::route('/{record}/edit'),
        ];
    }

    public static function getNavigationBadge(): ?string
    {
        try {
            return static::getModel()::where('type', 'client')->count();
        } catch (\Throwable $e) {
            return null;
        }
    }
}
