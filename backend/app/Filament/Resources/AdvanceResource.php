<?php

namespace App\Filament\Resources;

use App\Filament\Resources\AdvanceResource\Pages;
use App\Models\Advance;
use Filament\Schemas\Schema;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;

/**
 * Dedicated admin interface for "سلفني" (advance) withdrawals, kept
 * separate from the regular Transactions/Sales list as requested: shows
 * which customers took cards as an advance, how much they still owe, and
 * the settlement status.
 */
class AdvanceResource extends Resource
{
    protected static ?string $model = Advance::class;
    protected static ?int $navigationSort = 2;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-arrow-trending-up'; }
    public static function getNavigationLabel(): string { return 'سلفني (السلف)'; }
    public static function getNavigationGroup(): ?string { return 'المالية'; }

    public static function form(Schema $schema): Schema { return $schema->components([]); }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('transaction_number')->label('رقم العملية')->searchable(),
                Tables\Columns\TextColumn::make('user.name')->label('العميل')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('user.phone')->label('الهاتف')->searchable(),
                Tables\Columns\TextColumn::make('network.name')->label('الشبكة')->searchable(),
                Tables\Columns\TextColumn::make('category.name')->label('الفئة'),
                Tables\Columns\TextColumn::make('quantity')->label('عدد الكروت'),
                Tables\Columns\TextColumn::make('total_amount')->label('قيمة السلفة')->money('YER')->sortable(),
                Tables\Columns\TextColumn::make('repaid_amount')->label('المسدد')->money('YER'),
                Tables\Columns\TextColumn::make('advance_remaining')->label('المتبقي')->state(fn(Advance $r) => (float) $r->total_amount - (float) $r->repaid_amount)->money('YER'),
                Tables\Columns\BadgeColumn::make('advance_status')->label('الحالة')->colors([
                    'warning' => 'outstanding',
                    'info' => 'partially_repaid',
                    'success' => 'repaid',
                ])->formatStateUsing(fn($s) => match ($s) {
                    'outstanding' => 'مستحقة بالكامل',
                    'partially_repaid' => 'مسددة جزئياً',
                    'repaid' => 'مسددة بالكامل',
                    default => $s,
                }),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ السلفة')->dateTime('Y-m-d H:i')->sortable(),
                Tables\Columns\TextColumn::make('repaid_at')->label('تاريخ السداد')->dateTime('Y-m-d H:i'),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('advance_status')->label('حالة السداد')->options([
                    'outstanding' => 'مستحقة بالكامل',
                    'partially_repaid' => 'مسددة جزئياً',
                    'repaid' => 'مسددة بالكامل',
                ]),
                Tables\Filters\SelectFilter::make('network_id')->label('الشبكة')->relationship('network', 'name'),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50, 100]);
    }

    public static function canCreate(): bool { return false; }

    public static function getPages(): array
    {
        return ['index' => Pages\ListAdvances::route('/')];
    }

    public static function getNavigationBadge(): ?string
    {
        try {
            return static::getModel()::whereIn('advance_status', ['outstanding', 'partially_repaid'])->count() ?: null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    public static function getNavigationBadgeColor(): ?string { return 'warning'; }
}
