<?php

namespace App\Filament\Resources;

use App\Filament\Resources\NetworkOwnerResource\Pages;
use App\Models\NetworkOwner;
use Filament\Forms;
use Filament\Notifications\Notification;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\HtmlString;

class NetworkOwnerResource extends Resource
{
    protected static ?string $model = NetworkOwner::class;
    protected static ?int $navigationSort = 10;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-building-office-2'; }
    public static function getNavigationLabel(): string { return 'أصحاب الشبكات'; }
    public static function getNavigationGroup(): ?string { return 'إدارة الشبكات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            \Filament\Schemas\Components\Section::make('بيانات صاحب الشبكة')->schema([
                Forms\Components\Select::make('user_id')
                    ->label('المستخدم')
                    ->relationship('user', 'name')
                    ->searchable()
                    ->required(),
                Forms\Components\TextInput::make('business_name')->label('اسم النشاط التجاري'),
                Forms\Components\TextInput::make('national_id')->label('رقم الهوية'),
                Forms\Components\TextInput::make('bank_name')->label('اسم البنك'),
                Forms\Components\TextInput::make('bank_account')->label('رقم الحساب البنكي'),
                Forms\Components\TextInput::make('new_password')
                    ->label('كلمة مرور جديدة للمستخدم')
                    ->password()
                    ->minLength(6)
                    ->dehydrated(fn ($state) => filled($state))
                    ->helperText('اتركه فارغاً لعدم تغيير كلمة مرور صاحب الشبكة'),
                Forms\Components\Textarea::make('notes')->label('ملاحظات')->columnSpanFull(),
            ])->columns(2),
            \Filament\Schemas\Components\Section::make('بيانات المدفوعات والسحب')->schema([
                Forms\Components\TextInput::make('payout_full_name')->label('الاسم الرباعي'),
                Forms\Components\TextInput::make('payout_provider')->label('البنك أو المصرف / المحفظة'),
                Forms\Components\TextInput::make('payout_account_number')->label('رقم الحساب'),
            ])->columns(2),
            \Filament\Schemas\Components\Section::make('حالة الموافقة')->schema([
                Forms\Components\Toggle::make('is_approved')->label('موافق عليه'),
            ]),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->modifyQueryUsing(fn($query) => $query->with(['user.region']))
            ->columns([
                Tables\Columns\TextColumn::make('user.name')->label('صاحب الشبكة')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('user.phone')->label('الهاتف'),
                Tables\Columns\TextColumn::make('business_name')->label('النشاط التجاري'),
                Tables\Columns\TextColumn::make('user.region.type')
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
                Tables\Columns\TextColumn::make('networks_count')->label('الشبكات')->counts('networks'),
                Tables\Columns\TextColumn::make('user.available_balance')->label('الرصيد المتاح')->money('YER')->sortable(),
                Tables\Columns\TextColumn::make('user.total_earnings')->label('إجمالي الأرباح')->money('YER')->sortable(),
                Tables\Columns\TextColumn::make('is_approved')->label('الحالة')
                    ->formatStateUsing(fn($s) => $s ? 'تمت الموافقة' : 'قيد المراجعة')
                    ->badge()
                    ->color(fn($s) => $s ? 'success' : 'warning'),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ التسجيل')->date()->sortable(),
            ])
            ->filters([
                Tables\Filters\TernaryFilter::make('is_approved')->label('الحالة')
                    ->trueLabel('موافق عليهم')
                    ->falseLabel('قيد المراجعة'),
                Tables\Filters\SelectFilter::make('region_type')
                    ->label('المنطقة')
                    ->options([
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                    ])
                    ->query(function ($query, array $data) {
                        return $query->when($data['value'], fn($q) => $q->whereHas('user.region', fn($r) => $r->where('type', $data['value'])));
                    }),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\Action::make('approve')
                    ->label('موافقة')
                    ->icon('heroicon-o-check-circle')
                    ->color('success')
                    ->hidden(fn($r) => (bool)($r?->is_approved))
                    ->requiresConfirmation()
                    ->successRedirectUrl(static::getUrl('index'))
                    ->action(function ($record) {
                        DB::transaction(function () use ($record) {
                            $record->update([
                                'is_approved' => true,
                                'approved_at' => now(),
                                'approved_by' => auth()->id(),
                            ]);
                            $record->networks()->where('status', 'pending')->update([
                                'status' => 'active',
                                'approved_at' => now(),
                                'approved_by' => auth()->id(),
                            ]);
                            $record->user?->update(['type' => 'network_owner', 'is_active' => true]);
                        });
                        $record->refresh();
                        Notification::make()->title('تمت الموافقة على صاحب الشبكة وشبكاته')->success()->send();
                    }),
                \Filament\Actions\Action::make('view_networks')
                    ->label('عرض الشبكات')
                    ->icon('heroicon-o-wifi')
                    ->color('info')
                    ->modalHeading(fn($record) => 'شبكات ' . ($record->user?->name ?? 'صاحب الشبكة'))
                    ->modalSubmitAction(false)
                    ->modalCancelActionLabel('إغلاق')
                    ->modalContent(function ($record): HtmlString {
                        $networks = $record->networks()->latest()->get(['name', 'code', 'status']);
                        if ($networks->isEmpty()) {
                            return new HtmlString('<p class="fi-body text-sm text-gray-500">لا توجد شبكات مرتبطة بصاحب الشبكة.</p>');
                        }

                        $rows = $networks->map(function ($network): string {
                            $status = match ($network->status) {
                                'active' => 'تمت الموافقة',
                                'pending' => 'قيد المراجعة',
                                'rejected' => 'مرفوضة',
                                'suspended' => 'موقوفة',
                                default => e((string) $network->status),
                            };

                            return '<tr class="border-b"><td class="p-3">' . e($network->name) . '</td><td class="p-3">' . e($network->code ?? '-') . '</td><td class="p-3">' . $status . '</td></tr>';
                        })->implode('');

                        return new HtmlString('<div class="overflow-x-auto"><table class="w-full text-sm text-right"><thead><tr class="border-b"><th class="p-3">الشبكة</th><th class="p-3">الرقم</th><th class="p-3">الحالة</th></tr></thead><tbody>' . $rows . '</tbody></table></div>');
                    }),
            ])
            ->defaultSort('created_at', 'desc')
            ->poll('10s');
    }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListNetworkOwners::route('/'),
            'edit'   => Pages\EditNetworkOwner::route('/{record}/edit'),
        ];
    }

    public static function canCreate(): bool { return false; }

    public static function getNavigationBadge(): ?string
    {
        try {
            return static::getModel()::where(fn($q) => $q->where('is_approved', false)->orWhereNull('is_approved'))->count() ?: null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    public static function getNavigationBadgeColor(): ?string { return 'warning'; }
}
