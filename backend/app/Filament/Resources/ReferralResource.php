<?php

namespace App\Filament\Resources;

use App\Exports\ReferralsExport;
use App\Filament\Resources\ReferralResource\Pages;
use App\Models\Referral;
use App\Models\WalletLog;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Facades\DB;
use Filament\Forms;
use Filament\Notifications\Notification;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;
use Maatwebsite\Excel\Facades\Excel;

class ReferralResource extends Resource
{
    protected static ?string $model = Referral::class;
    protected static ?int $navigationSort = 3;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-link'; }
    public static function getNavigationLabel(): string { return 'الرفلينك والإحالات'; }
    public static function getNavigationGroup(): ?string { return 'المالية'; }

    public static function form(Schema $schema): Schema { return $schema->components([]); }

    public static function table(Table $table): Table
    {
        return $table
            ->modifyQueryUsing(fn ($query) => $query->with([
                'referrer.region', 'referred.region',
                'transaction.network.owner', 'transaction.network.region', 'transaction.category',
            ]))
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#')->sortable(),
                Tables\Columns\TextColumn::make('referrer.name')->label('صاحب الرابط')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('referrer.phone')->label('هاتف صاحب الرابط'),
                Tables\Columns\TextColumn::make('referrer.region.type')
                    ->label('منطقة صاحب الرابط')
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                        default => '—',
                    })
                    ->badge(),
                Tables\Columns\TextColumn::make('referred.name')
                    ->label('المسجّل / الشبكة')
                    ->searchable()
                    ->formatStateUsing(function ($state, $record) {
                        if ($record->transaction_id) {
                            $network = $record->transaction?->network?->name ?? '—';
                            $category = $record->transaction?->category?->name;
                            return 'عمولة كرت شبكة: ' . $network . ($category ? ' (' . $category . ')' : '');
                        }
                        return $state ?? '—';
                    }),
                Tables\Columns\TextColumn::make('referred.phone')
                    ->label('هاتف المسجّل / صاحب الشبكة')
                    ->formatStateUsing(function ($state, $record) {
                        if ($record->transaction_id) {
                            return $record->transaction?->network?->owner?->phone
                                ?? $record->transaction?->network?->phone ?? '—';
                        }
                        return $state ?? '—';
                    }),
                Tables\Columns\TextColumn::make('referred_region_display')
                    ->label('منطقة المسجّل / الشبكة')
                    ->state(function ($record) {
                        if ($record->transaction_id) {
                            return $record->transaction?->network?->region?->type;
                        }
                        return $record->referred?->region?->type;
                    })
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                        default => '—',
                    })
                    ->badge(),
                Tables\Columns\TextColumn::make('commission_amount')
                    ->label('مبلغ العمولة')
                    ->formatStateUsing(fn($state) => number_format($state, 0) . ' ريال')
                    ->sortable(),
                Tables\Columns\TextColumn::make('commission_percentage')->label('نسبة العمولة %')->suffix('%'),
                Tables\Columns\IconColumn::make('is_paid')->label('مدفوعة')->boolean(),
                Tables\Columns\TextColumn::make('paid_at')->label('تاريخ الدفع')->dateTime()->placeholder('لم تُدفع بعد'),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإحالة')->date()->sortable(),
            ])
            ->filters([
                Tables\Filters\TernaryFilter::make('is_paid')->label('حالة الدفع')
                    ->trueLabel('مدفوعة')->falseLabel('غير مدفوعة'),
                Tables\Filters\SelectFilter::make('region')
                    ->label('المنطقة')
                    ->options([
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                    ])
                    ->query(fn ($query, array $data) => $query->when(
                        $data['value'] ?? null,
                        fn ($q, $value) => $q->whereHas('referrer.region', fn ($r) => $r->where('type', $value))
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
                                ->with(['referrer.region', 'referred.region'])
                                ->when($from, fn ($q, $v) => $q->whereDate('created_at', '>=', $v))
                                ->when($until, fn ($q, $v) => $q->whereDate('created_at', '<=', $v))
                                ->when($regionType, fn ($q, $v) => $q->whereHas('referrer.region', fn ($r) => $r->where('type', $v)))
                                ->latest()
                                ->get();

                            return \Barryvdh\DomPDF\Facade\Pdf::loadView('exports.referrals-pdf', compact('records', 'from', 'until'))
                                ->download("referrals-{$suffix}.pdf");
                        }

                        return \Maatwebsite\Excel\Facades\Excel::download(
                            new ReferralsExport($query, $from, $until, $regionType),
                            "referrals-{$suffix}.xlsx"
                        );
                    }),
            ])
            ->actions([
                \Filament\Actions\Action::make('mark_paid')
                    ->label('تعيين كـ مدفوعة')
                    ->icon('heroicon-o-check-circle')
                    ->color('success')
                    ->visible(fn($record) => !$record->is_paid)
                    ->requiresConfirmation()
                    ->modalHeading('تأكيد دفع العمولة')
                    ->modalDescription(fn($record) => 'هل تريد تأكيد دفع عمولة قدرها ' . number_format($record->commission_amount, 0) . ' ريال لـ ' . $record->referrer?->name . '؟')
                    ->action(function ($record) {
                        DB::transaction(function () use ($record) {
                            $beneficiary = $record->referrer;
                            if (!$beneficiary) {
                                return;
                            }

                            $record->update(['is_paid' => true, 'paid_at' => now()]);

                            $balanceBefore = (float) $beneficiary->balance;
                            $beneficiary->increment('balance', $record->commission_amount);
                            $beneficiary->increment('available_balance', $record->commission_amount);

                            WalletLog::create([
                                'user_id' => $beneficiary->id,
                                'type' => 'referral_commission',
                                'amount' => $record->commission_amount,
                                'balance_before' => $balanceBefore,
                                'balance_after' => (float) $beneficiary->fresh()->balance,
                                'description' => 'صرف عمولة إحالة - عملية شراء رقم ' . ($record->transaction?->transaction_number ?? $record->id),
                                'reference_type' => 'referral_payout',
                                'reference_id' => $record->id,
                            ]);
                        });

                        Notification::make()->title('تم دفع العمولة وإضافتها لرصيد المستفيد')->success()->send();
                    }),
            ])
            ->bulkActions([
                \Filament\Actions\BulkAction::make('bulk_pay')
                    ->label('دفع المحدد')
                    ->icon('heroicon-o-banknotes')
                    ->color('success')
                    ->requiresConfirmation()
                    ->action(function ($records) {
                        DB::transaction(function () use ($records) {
                            foreach ($records as $record) {
                                if ($record->is_paid) {
                                    continue;
                                }

                                $beneficiary = $record->referrer;
                                if (!$beneficiary) {
                                    continue;
                                }

                                $record->update(['is_paid' => true, 'paid_at' => now()]);

                                $balanceBefore = (float) $beneficiary->balance;
                                $beneficiary->increment('balance', $record->commission_amount);
                                $beneficiary->increment('available_balance', $record->commission_amount);

                                WalletLog::create([
                                    'user_id' => $beneficiary->id,
                                    'type' => 'referral_commission',
                                    'amount' => $record->commission_amount,
                                    'balance_before' => $balanceBefore,
                                    'balance_after' => (float) $beneficiary->fresh()->balance,
                                    'description' => 'صرف عمولة إحالة - عملية شراء رقم ' . ($record->transaction?->transaction_number ?? $record->id),
                                    'reference_type' => 'referral_payout',
                                    'reference_id' => $record->id,
                                ]);
                            }
                        });

                        Notification::make()->title('تم دفع العمولات المحددة')->success()->send();
                    }),
            ])
            ->defaultSort('created_at', 'desc')
            ->poll('10s');
    }

    public static function canCreate(): bool { return false; }

    public static function getPages(): array
    {
        return ['index' => Pages\ListReferrals::route('/')];
    }

    public static function getNavigationBadge(): ?string
    {
        try {
            $count = static::getModel()::where('is_paid', false)->count();
            return $count > 0 ? (string) $count : null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    public static function getNavigationBadgeColor(): ?string { return 'warning'; }
}
