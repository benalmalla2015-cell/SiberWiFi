<?php

namespace App\Filament\Resources;

use App\Exports\PayoutRequestsExport;
use App\Filament\Resources\PayoutRequestResource\Pages;
use App\Models\PayoutRequest;
use App\Models\WalletLog;
use App\Services\NotificationService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;
use Maatwebsite\Excel\Facades\Excel;

class PayoutRequestResource extends Resource
{
    protected static ?string $model = PayoutRequest::class;
    protected static ?int $navigationSort = 2;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-currency-dollar'; }
    public static function getNavigationLabel(): string { return 'طلبات السحب'; }
    public static function getNavigationGroup(): ?string { return 'المالية'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            \Filament\Schemas\Components\Section::make('معلومات الطلب')->schema([
                Forms\Components\TextInput::make('request_number')->label('رقم الطلب')->disabled(),
                Forms\Components\Select::make('user_id')
                    ->label('صاحب الشبكة')
                    ->relationship('user', 'name')
                    ->searchable(['name', 'phone'])
                    ->disabled()
                    ->required(),
                Forms\Components\TextInput::make('amount')->label('المبلغ المطلوب')->numeric()->required(),
                Forms\Components\Select::make('status')
                    ->label('الحالة')
                    ->options([
                        'pending' => 'قيد المراجعة',
                        'approved' => 'تمت الموافقة',
                        'paid_unconfirmed' => 'تم الصرف - بانتظار التأكيد',
                        'received' => 'مكتمل',
                        'rejected' => 'مرفوض',
                    ])
                    ->required(),
            ])->columns(2),
            \Filament\Schemas\Components\Section::make('بيانات المدفوعات والسحب')->schema([
                Forms\Components\TextInput::make('payout_full_name')
                    ->label('الاسم الرباعي')
                    ->disabled()
                    ->default(fn($record) => $record?->payout_full_name ?? $record?->user?->networkOwnerProfile?->payout_full_name ?? '—')
                    ->dehydrated(false),
                Forms\Components\TextInput::make('payout_provider')
                    ->label('البنك أو المصرف / المحفظة')
                    ->disabled()
                    ->default(fn($record) => $record?->payout_provider ?? $record?->user?->networkOwnerProfile?->payout_provider ?? '—')
                    ->dehydrated(false),
                Forms\Components\TextInput::make('payout_account_number')
                    ->label('رقم الحساب')
                    ->disabled()
                    ->default(fn($record) => $record?->payout_account_number ?? $record?->user?->networkOwnerProfile?->payout_account_number ?? '—')
                    ->dehydrated(false),
            ])->columns(1),
            \Filament\Schemas\Components\Section::make('معلومات الدفع')->schema([
                Forms\Components\TextInput::make('paid_amount')->label('المبلغ المدفوع')->numeric(),
                Forms\Components\TextInput::make('service_name')->label('وسيلة الدفع'),
                Forms\Components\TextInput::make('transaction_number')->label('رقم العملية'),
            ])->columns(2),
            \Filament\Schemas\Components\Section::make('ملاحظات')->schema([
                Forms\Components\Textarea::make('admin_notes')->label('ملاحظات الإدارة')->rows(3),
            ]),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->modifyQueryUsing(fn ($query) => $query->with(['user.region', 'user.networkOwnerProfile']))
            ->columns([
                Tables\Columns\TextColumn::make('request_number')->label('رقم الطلب')->searchable(),
                Tables\Columns\TextColumn::make('user.name')->label('صاحب الشبكة')->searchable(),
                Tables\Columns\TextColumn::make('user.region.type')
                    ->label('المنطقة')
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                        default => '—',
                    }),
                Tables\Columns\TextColumn::make('user.phone')->label('الهاتف')->searchable(),
                Tables\Columns\TextColumn::make('payout_full_name')
                    ->label('الاسم الرباعي')
                    ->default(fn($record) => $record?->payout_full_name ?? $record?->user?->networkOwnerProfile?->payout_full_name ?? '—'),
                Tables\Columns\TextColumn::make('payout_provider')
                    ->label('البنك/المحفظة')
                    ->default(fn($record) => $record?->payout_provider ?? $record?->user?->networkOwnerProfile?->payout_provider ?? '—'),
                Tables\Columns\TextColumn::make('payout_account_number')
                    ->label('رقم الحساب')
                    ->default(fn($record) => $record?->payout_account_number ?? $record?->user?->networkOwnerProfile?->payout_account_number ?? '—'),
                Tables\Columns\TextColumn::make('amount')->label('المبلغ المطلوب')->money('YER')->sortable(),
                Tables\Columns\TextColumn::make('paid_amount')->label('المبلغ المدفوع')->money('YER'),
                Tables\Columns\BadgeColumn::make('status')
                    ->label('الحالة')
                    ->colors([
                        'warning' => 'pending',
                        'primary' => 'approved',
                        'success' => 'paid_unconfirmed',
                        'success' => 'received',
                        'danger' => 'rejected',
                    ])
                    ->formatStateUsing(fn($s) => match($s) {
                        'pending' => 'قيد المراجعة',
                        'approved' => 'تمت الموافقة',
                        'paid_unconfirmed' => 'تم الصرف - بانتظار التأكيد',
                        'received' => 'مكتمل',
                        'rejected' => 'مرفوض',
                        default => $s,
                    }),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الطلب')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('status')->label('الحالة')->options([
                    'pending' => 'قيد المراجعة',
                    'approved' => 'تمت الموافقة',
                    'paid_unconfirmed' => 'تم الصرف - بانتظار التأكيد',
                    'received' => 'مكتمل',
                    'rejected' => 'مرفوض',
                ]),
                Tables\Filters\SelectFilter::make('region')
                    ->label('المنطقة')
                    ->options([
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                    ])
                    ->query(fn ($query, array $data) => $query->when(
                        $data['value'] ?? null,
                        fn ($q, $value) => $q->whereHas('user.region', fn ($r) => $r->where('type', $value))
                    )),
            ])
            ->headerActions([
                \Filament\Actions\Action::make('export')
                    ->label('تصدير Excel/PDF')
                    ->icon('heroicon-o-arrow-down-tray')
                    ->color('success')
                    ->form([
                        Forms\Components\DatePicker::make('from')->label('من تاريخ'),
                        Forms\Components\DatePicker::make('until')->label('إلى تاريخ'),
                        Forms\Components\Select::make('region')
                            ->label('المنطقة')
                            ->options([
                                'north' => 'الشمال',
                                'south' => 'الجنوب',
                            ])
                            ->placeholder('الكل'),
                        Forms\Components\Select::make('format')
                            ->label('صيغة التصدير')
                            ->options([
                                'excel' => 'Excel',
                                'pdf' => 'PDF',
                            ])
                            ->default('excel')
                            ->required(),
                    ])
                    ->action(function (array $data, $livewire) {
                        $query = $livewire->getFilteredTableQuery();
                        $from = $data['from'] ?? null;
                        $until = $data['until'] ?? null;
                        $regionType = $data['region'] ?? null;
                        $format = $data['format'] ?? 'excel';
                        $suffix = now()->format('Y-m-d-His');

                        if ($format === 'pdf') {
                            $records = (clone $query)
                                ->with(['user.region'])
                                ->when($from, fn ($q, $v) => $q->whereDate('created_at', '>=', $v))
                                ->when($until, fn ($q, $v) => $q->whereDate('created_at', '<=', $v))
                                ->when($regionType, fn ($q, $v) => $q->whereHas('user.region', fn ($r) => $r->where('type', $v)))
                                ->latest()
                                ->get();

                            return Pdf::loadView('exports.payout-requests-pdf', compact('records', 'from', 'until'))
                                ->download("payout-requests-{$suffix}.pdf");
                        }

                        return Excel::download(
                            new PayoutRequestsExport($query, $from, $until, $regionType),
                            "payout-requests-{$suffix}.xlsx"
                        );
                    }),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('معالجة'),
                \Filament\Actions\Action::make('approve')
                    ->label('موافقة')
                    ->icon('heroicon-o-check-circle')
                    ->color('primary')
                    ->requiresConfirmation()
                    ->action(function (PayoutRequest $record) {
                        $record->update(['status' => 'approved']);
                        try {
                            app(NotificationService::class)->send(
                                $record->user,
                                'تمت الموافقة على طلب السحب',
                                'تمت الموافقة على طلب سحبك بمبلغ ' . number_format($record->amount) . ' ريال.',
                                ['type' => 'payout_approved', 'payout_id' => $record->id]
                            );
                        } catch (\Throwable $e) {
                            \Log::warning('Payout approval notification failed: ' . $e->getMessage());
                        }
                    })
                    ->visible(fn(?PayoutRequest $record) => $record?->status === 'pending'),
                \Filament\Actions\Action::make('markPaid')
                    ->label('تسجيل الدفع')
                    ->icon('heroicon-o-banknotes')
                    ->color('success')
                    ->modalHeading('تسجيل الدفع')
                    ->modalDescription('سيتم خصم المبلغ المدفوع من رصيد صاحب الشبكة وإرسال إشعار له.')
                    ->modalSubmitActionLabel('تأكيد')
                    ->form([
                        Forms\Components\TextInput::make('paid_amount')->label('المبلغ المدفوع')->numeric()->minValue(1)->required(),
                        Forms\Components\TextInput::make('service_name')->label('وسيلة الدفع')->required(),
                        Forms\Components\TextInput::make('transaction_number')->label('رقم العملية'),
                        Forms\Components\Textarea::make('admin_notes')->label('ملاحظات الإدارة')->rows(3),
                    ])
                    ->action(function (PayoutRequest $record, array $data) {
                        $record->update([
                            'paid_amount' => $data['paid_amount'],
                            'service_name' => $data['service_name'],
                            'transaction_number' => $data['transaction_number'] ?? null,
                            'admin_notes' => $data['admin_notes'] ?? null,
                            'status' => 'paid_unconfirmed',
                            'paid_at' => now(),
                            'processed_by' => auth()->id(),
                        ]);
                        $record->refresh();
                        try {
                            app(NotificationService::class)->send(
                                $record->user,
                                'تم صرف مبلغ السحب',
                                'تم صرف مبلغ ' . number_format($record->paid_amount) . ' ريال عبر ' . $record->service_name . '. يرجى تأكيد الاستلام.',
                                ['type' => 'payout_paid', 'payout_id' => $record->id]
                            );
                        } catch (\Throwable $e) {
                            \Log::warning('Payout paid notification failed: ' . $e->getMessage());
                        }
                    })
                    ->visible(fn(?PayoutRequest $record) => in_array($record?->status, ['pending', 'approved'], true)),
                \Filament\Actions\Action::make('reject')
                    ->label('رفض')
                    ->icon('heroicon-o-x-circle')
                    ->color('danger')
                    ->modalHeading('رفض طلب السحب')
                    ->modalSubmitActionLabel('تأكيد الرفض')
                    ->form([
                        Forms\Components\Textarea::make('rejection_reason')->label('سبب الرفض')->required()->rows(3),
                    ])
                    ->action(function (PayoutRequest $record, array $data) {
                        $record->update([
                            'status' => 'rejected',
                            'rejection_reason' => $data['rejection_reason'],
                            'admin_notes' => $data['rejection_reason'],
                            'processed_by' => auth()->id(),
                        ]);
                        try {
                            app(NotificationService::class)->send(
                                $record->user,
                                'تم رفض طلب السحب',
                                'تم رفض طلب سحبك بمبلغ ' . number_format($record->amount) . ' ريال. السبب: ' . $data['rejection_reason'],
                                ['type' => 'payout_rejected', 'payout_id' => $record->id]
                            );
                        } catch (\Throwable $e) {
                            \Log::warning('Payout rejection notification failed: ' . $e->getMessage());
                        }
                    })
                    ->visible(fn(?PayoutRequest $record) => in_array($record?->status, ['pending', 'approved'], true)),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50, 100])
            ->poll('10s');
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListPayoutRequests::route('/'),
            'edit'  => Pages\EditPayoutRequest::route('/{record}/edit'),
        ];
    }
}
