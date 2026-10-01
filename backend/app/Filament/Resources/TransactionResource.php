<?php

namespace App\Filament\Resources;

use App\Exports\TransactionsExport;
use App\Filament\Resources\TransactionResource\Pages;
use App\Models\Transaction;
use Barryvdh\DomPDF\Facade\Pdf;
use Filament\Forms;
use Filament\Schemas\Schema;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;
use Maatwebsite\Excel\Facades\Excel;

class TransactionResource extends Resource
{
    protected static ?string $model = Transaction::class;
    protected static ?int $navigationSort = 1;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-banknotes'; }
    public static function getNavigationLabel(): string { return 'المعاملات'; }
    public static function getNavigationGroup(): ?string { return 'المالية'; }

    public static function form(Schema $schema): Schema { return $schema->components([]); }

    public static function table(Table $table): Table
    {
        return $table
            ->modifyQueryUsing(fn ($query) => $query->with(['user.region']))
            ->columns([
                Tables\Columns\TextColumn::make('transaction_number')->label('رقم المعاملة')->searchable(),
                Tables\Columns\TextColumn::make('user.name')->label('العميل')->searchable(),
                Tables\Columns\TextColumn::make('network.name')->label('الشبكة')->searchable(),
                Tables\Columns\TextColumn::make('user.region.type')
                    ->label('المنطقة')
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'north' => 'الشمال',
                        'south' => 'الجنوب',
                        default => '—',
                    }),
                Tables\Columns\TextColumn::make('category.name')->label('الفئة'),
                Tables\Columns\TextColumn::make('quantity')->label('الكمية'),
                Tables\Columns\TextColumn::make('total_amount')->label('الإجمالي')->money('YER')->sortable(),
                Tables\Columns\TextColumn::make('commission_amount')->label('العمولة')->money('YER'),
                Tables\Columns\TextColumn::make('network_owner_amount')->label('للمالك')->money('YER'),
                Tables\Columns\TextColumn::make('cashback_amount')->label('كاشباك')->money('YER'),
                Tables\Columns\BadgeColumn::make('status')->label('الحالة')->colors([
                    'success' => 'completed', 'warning' => 'pending', 'danger' => 'failed',
                ])->formatStateUsing(fn($s) => match($s) {
                    'completed' => 'مكتملة', 'pending' => 'معلقة', 'failed' => 'فاشلة', default => $s,
                }),
                Tables\Columns\TextColumn::make('created_at')->label('التاريخ')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('status')->label('الحالة')->options([
                    'completed' => 'مكتملة', 'pending' => 'معلقة', 'failed' => 'فاشلة',
                ]),
                Tables\Filters\Filter::make('created_at')
                    ->form([
                        \Filament\Forms\Components\DatePicker::make('from')->label('من'),
                        \Filament\Forms\Components\DatePicker::make('to')->label('إلى'),
                    ])
                    ->query(fn($query, array $data) => $query
                        ->when($data['from'], fn($q, $v) => $q->whereDate('created_at', '>=', $v))
                        ->when($data['to'],   fn($q, $v) => $q->whereDate('created_at', '<=', $v))
                    ),
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
                                ->with(['user.region', 'network:id,name', 'category:id,name'])
                                ->when($from, fn ($q, $v) => $q->whereDate('created_at', '>=', $v))
                                ->when($until, fn ($q, $v) => $q->whereDate('created_at', '<=', $v))
                                ->when($regionType, fn ($q, $v) => $q->whereHas('user.region', fn ($r) => $r->where('type', $v)))
                                ->latest()
                                ->get();

                            return Pdf::loadView('exports.transactions-pdf', compact('records', 'from', 'until'))
                                ->download("transactions-{$suffix}.pdf");
                        }

                        return Excel::download(
                            new TransactionsExport($query, $from, $until, $regionType),
                            "transactions-{$suffix}.xlsx"
                        );
                    }),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50, 100])
            ->poll('10s');
    }

    public static function canCreate(): bool { return false; }

    public static function getPages(): array
    {
        return ['index' => Pages\ListTransactions::route('/')];
    }

    public static function getNavigationBadge(): ?string
    {
        try {
            return number_format(static::getModel()::where('status', 'completed')->sum('total_amount'));
        } catch (\Throwable $e) {
            return null;
        }
    }
}
