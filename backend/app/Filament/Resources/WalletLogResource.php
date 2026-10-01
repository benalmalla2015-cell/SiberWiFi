<?php

namespace App\Filament\Resources;

use App\Exports\WalletLogsExport;
use App\Filament\Resources\WalletLogResource\Pages;
use App\Models\WalletLog;
use App\Services\NotificationService;
use Barryvdh\DomPDF\Facade\Pdf;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;
use Illuminate\Support\Facades\DB;
use Maatwebsite\Excel\Facades\Excel;

class WalletLogResource extends Resource
{
    protected static ?string $model = WalletLog::class;
    protected static ?int $navigationSort = 4;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-clipboard-document-list'; }
    public static function getNavigationLabel(): string { return 'سجل المحافظ'; }
    public static function getNavigationGroup(): ?string { return 'المالية'; }

    public static function form(Schema $schema): Schema { return $schema->components([]); }

    public static function table(Table $table): Table
    {
        return $table
            ->modifyQueryUsing(fn ($query) => $query->with(['user.region']))
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#')->sortable(),
                Tables\Columns\TextColumn::make('user.name')->label('المستخدم')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('user.region.type')
                    ->label('المنطقة')
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                        default => '—',
                    }),
                Tables\Columns\TextColumn::make('user.phone')->label('الهاتف')->searchable(),
                Tables\Columns\BadgeColumn::make('type')->label('النوع')
                    ->colors([
                        'success' => 'credit',
                        'danger' => ['debit', 'rejected_topup'],
                        'warning' => 'pending_topup',
                    ])
                    ->formatStateUsing(fn($state) => match ($state) {
                        'credit' => 'إيداع',
                        'debit' => 'خصم',
                        'pending_topup' => 'طلب شحن (بانتظار المراجعة)',
                        'rejected_topup' => 'طلب شحن مرفوض',
                        default => $state,
                    }),
                Tables\Columns\TextColumn::make('amount')
                    ->label('المبلغ')
                    ->formatStateUsing(fn($state) => number_format($state, 0) . ' ريال')
                    ->sortable(),
                Tables\Columns\TextColumn::make('balance_before')
                    ->label('الرصيد قبل')
                    ->formatStateUsing(fn($state) => number_format($state, 0)),
                Tables\Columns\TextColumn::make('balance_after')
                    ->label('الرصيد بعد')
                    ->formatStateUsing(fn($state) => number_format($state, 0)),
                Tables\Columns\TextColumn::make('description')->label('الوصف')->limit(40)->tooltip(fn($record) => $record->description),
                Tables\Columns\TextColumn::make('bankAccount.owner_name')->label('صاحب الحساب')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('bankAccount.bank_name')->label('اسم الحساب المصرفي')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('bankAccount.account_number')->label('رقم الحساب')->searchable()->copyable(),
                Tables\Columns\TextColumn::make('transfer_receipt_number')->label('رقم السند/الحوالة')->searchable()->copyable(),
                Tables\Columns\TextColumn::make('sender_name')->label('اسم المودع/المرسل')->searchable(),
                Tables\Columns\ImageColumn::make('receipt_image')
                    ->label('صورة السند')
                    ->disk('public')
                    ->width(60)
                    ->height(60)
                    ->circular(false)
                    ->action(
                        \Filament\Actions\Action::make('viewReceiptImage')
                            ->label('عرض صورة السند')
                            ->modalHeading('صورة السند')
                            ->modalContent(fn (WalletLog $record) => view('filament.receipt-image-modal', ['record' => $record]))
                            ->modalSubmitAction(false)
                            ->modalCancelActionLabel('إغلاق')
                    ),
                Tables\Columns\TextColumn::make('reference_type')->label('المرجع')->badge(),
                Tables\Columns\TextColumn::make('created_at')->label('التاريخ والوقت')->dateTime('Y-m-d H:i')->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('type')->label('النوع')->options([
                    'credit' => 'إيداع',
                    'debit'  => 'خصم',
                    'pending_topup' => 'طلب شحن (بانتظار المراجعة)',
                    'rejected_topup' => 'طلب شحن مرفوض',
                ]),
                Tables\Filters\SelectFilter::make('reference_type')->label('المرجع')->options([
                    'purchase' => 'شراء',
                    'manual'   => 'يدوي',
                    'cashback' => 'كاشباك',
                    'referral' => 'رفلينك',
                    'topup_request' => 'طلب شحن رصيد',
                ]),
                Tables\Filters\Filter::make('created_at')
                    ->form([
                        \Filament\Forms\Components\DatePicker::make('from')->label('من تاريخ'),
                        \Filament\Forms\Components\DatePicker::make('until')->label('إلى تاريخ'),
                    ])
                    ->query(function ($query, array $data) {
                        return $query
                            ->when($data['from'], fn($q) => $q->whereDate('created_at', '>=', $data['from']))
                            ->when($data['until'], fn($q) => $q->whereDate('created_at', '<=', $data['until']));
                    }),
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

                            return Pdf::loadView('exports.wallet-logs-pdf', compact('records', 'from', 'until'))
                                ->download("wallet-logs-{$suffix}.pdf");
                        }

                        return Excel::download(
                            new WalletLogsExport($query, $from, $until, $regionType),
                            "wallet-logs-{$suffix}.xlsx"
                        );
                    }),
            ])
            ->actions([
                \Filament\Actions\Action::make('approveTopup')
                    ->label('موافقة')
                    ->icon('heroicon-o-check-circle')
                    ->color('success')
                    ->requiresConfirmation()
                    ->modalHeading('الموافقة على طلب الشحن')
                    ->modalDescription('في حال وجود سلفة "سلفني" مستحقة على المستخدم، سيتم خصمها أولاً من مبلغ الشحن قبل إضافة أي رصيد قابل للاستخدام.')
                    ->action(function (WalletLog $record) {
                        $repaidAmount = 0.0;
                        $remainderCredited = 0.0;

                        DB::transaction(function () use ($record, &$repaidAmount, &$remainderCredited) {
                            $log = WalletLog::lockForUpdate()->findOrFail($record->id);

                            if ($log->type !== 'pending_topup') {
                                return;
                            }

                            $user = $log->user()->lockForUpdate()->firstOrFail();
                            $balanceBefore = (float) $user->balance;

                            $settlement = app(\App\Services\AdvanceService::class)->settleFromTopup($user, (float) $log->amount);
                            $repaidAmount = $settlement['repaid'];
                            $remainderCredited = $settlement['remainder'];

                            if ($remainderCredited > 0) {
                                $user->increment('balance', $remainderCredited);
                                $user->increment('available_balance', $remainderCredited);
                            }
                            $user->refresh();

                            $description = $log->description . ' - تمت الموافقة';
                            if ($repaidAmount > 0) {
                                $description .= ' (تم خصم ' . number_format($repaidAmount) . ' ريال سداداً لسلفة "سلفني"، وأُضيف ' . number_format($remainderCredited) . ' ريال إلى الرصيد)';
                            }

                            $log->update([
                                'type' => 'credit',
                                'balance_before' => $balanceBefore,
                                'balance_after' => (float) $user->balance,
                                'description' => $description,
                            ]);
                        });

                        $record->refresh();
                        try {
                            $body = $repaidAmount > 0
                                ? 'تمت الموافقة على شحن رصيدك بمبلغ ' . number_format($record->amount) . ' ريال. تم خصم ' . number_format($repaidAmount) . ' ريال سداداً لسلفة "سلفني" المستحقة، وأُضيف ' . number_format($remainderCredited) . ' ريال إلى رصيدك.'
                                : 'تمت الموافقة على طلب شحن رصيدك بمبلغ ' . number_format($record->amount) . ' ريال وتمت إضافته إلى رصيدك.';
                            app(NotificationService::class)->send(
                                $record->user,
                                'تمت الموافقة على طلب الشحن',
                                $body,
                                ['type' => 'topup_approved', 'wallet_log_id' => $record->id]
                            );
                        } catch (\Throwable $e) {
                            \Log::warning('Topup approval notification failed: ' . $e->getMessage());
                        }
                    })
                    ->visible(fn(?WalletLog $record) => $record?->type === 'pending_topup'),
                \Filament\Actions\Action::make('rejectTopup')
                    ->label('رفض')
                    ->icon('heroicon-o-x-circle')
                    ->color('danger')
                    ->requiresConfirmation()
                    ->modalHeading('رفض طلب الشحن')
                    ->modalDescription('لن تتم إضافة أي مبلغ إلى رصيد المستخدم.')
                    ->form([
                        Forms\Components\Textarea::make('reason')->label('سبب الرفض (اختياري)')->rows(3),
                    ])
                    ->action(function (WalletLog $record, array $data) {
                        $record->update([
                            'type' => 'rejected_topup',
                            'description' => $record->description . ' - مرفوض' . (!empty($data['reason']) ? (': ' . $data['reason']) : ''),
                        ]);

                        try {
                            app(NotificationService::class)->send(
                                $record->user,
                                'تم رفض طلب الشحن',
                                'تم رفض طلب شحن رصيدك بمبلغ ' . number_format($record->amount) . ' ريال.' . (!empty($data['reason']) ? (' السبب: ' . $data['reason']) : ''),
                                ['type' => 'topup_rejected', 'wallet_log_id' => $record->id]
                            );
                        } catch (\Throwable $e) {
                            \Log::warning('Topup rejection notification failed: ' . $e->getMessage());
                        }
                    })
                    ->visible(fn(?WalletLog $record) => $record?->type === 'pending_topup'),
            ])
            ->defaultSort('created_at', 'desc')
            ->poll('10s');
    }

    public static function canCreate(): bool { return false; }

    public static function getPages(): array
    {
        return ['index' => Pages\ListWalletLogs::route('/')];
    }
}
