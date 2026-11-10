<?php

namespace App\Filament\Resources;

use App\Filament\Resources\TopupOrderResource\Pages;
use App\Models\TopupOrder;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class TopupOrderResource extends Resource
{
    protected static ?string $model = TopupOrder::class;
    protected static ?int $navigationSort = 5;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-clipboard-document-list'; }
    public static function getNavigationLabel(): string { return 'عمليات الشحن الفوري'; }
    public static function getNavigationGroup(): ?string { return 'الشحن الفوري'; }
    public static function getModelLabel(): string { return 'عملية شحن'; }
    public static function getPluralModelLabel(): string { return 'عمليات الشحن الفوري'; }

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()->with('user')->latest();
    }

    public static function canCreate(): bool { return false; }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('id')
                    ->label('#')
                    ->sortable()
                    ->toggleable(),
                Tables\Columns\TextColumn::make('user.name')
                    ->label('العميل')
                    ->description(fn (TopupOrder $r) => $r->user?->phone)
                    ->searchable()
                    ->sortable(),
                Tables\Columns\TextColumn::make('user.phone')
                    ->label('جوال العميل')
                    ->searchable()
                    ->toggleable(),
                Tables\Columns\TextColumn::make('user.type')
                    ->label('نوع الحساب')
                    ->badge()
                    ->formatStateUsing(fn (?string $v) => match ($v) {
                        'network_owner' => 'صاحب شبكة',
                        'client' => 'عميل',
                        'pos' => 'نقطة بيع',
                        'distributor' => 'موزع',
                        default => $v ?? '—',
                    })
                    ->color(fn (?string $v) => match ($v) {
                        'network_owner' => 'warning',
                        'pos', 'distributor' => 'info',
                        default => 'gray',
                    }),
                Tables\Columns\TextColumn::make('user.region_type')
                    ->label('المنطقة')
                    ->badge()
                    ->formatStateUsing(fn (?string $v) => match ($v) {
                        'south' => 'الجنوب',
                        'north' => 'الشمال',
                        default => $v ?? '—',
                    })
                    ->color(fn (?string $v) => $v === 'north' ? 'success' : 'primary'),
                Tables\Columns\TextColumn::make('service_code')
                    ->label('الخدمة')
                    ->badge()
                    ->searchable(),
                Tables\Columns\TextColumn::make('account')
                    ->label('البوابة')
                    ->formatStateUsing(fn (?string $v) => $v === 'north' ? 'شمال' : 'جنوب')
                    ->toggleable(),
                Tables\Columns\TextColumn::make('target')
                    ->label('الرقم المستهدف')
                    ->searchable()
                    ->copyable(),
                Tables\Columns\TextColumn::make('amount')
                    ->label('مبلغ المزود')
                    ->numeric(2)
                    ->sortable(),
                Tables\Columns\TextColumn::make('fee')
                    ->label('العمولة')
                    ->numeric(2),
                Tables\Columns\TextColumn::make('total_charged')
                    ->label('المخصوم من المحفظة')
                    ->numeric(2)
                    ->sortable(),
                Tables\Columns\TextColumn::make('provider_price')
                    ->label('تكلفة المزود')
                    ->numeric(2)
                    ->placeholder('—'),
                Tables\Columns\TextColumn::make('profit')
                    ->label('الربح')
                    ->state(function (TopupOrder $r) {
                        if ($r->status !== 'done' || $r->provider_price === null) return null;
                        // نفس البوابة = نفس العملة → طرح مباشر صحيح.
                        // بوابة مغايرة = المخصوم بعملة العميل والتكلفة بعملة البوابة — العمولة هي الربح الموثّق.
                        $sameCurrency = $r->user?->region_type === $r->account;
                        return $sameCurrency
                            ? ($r->total_charged - $r->provider_price)
                            : $r->fee;
                    })
                    ->numeric(2)
                    ->color(fn ($state) => $state === null ? 'gray' : ($state >= 0 ? 'success' : 'danger'))
                    ->placeholder('—'),
                Tables\Columns\TextColumn::make('status')
                    ->label('الحالة')
                    ->badge()
                    ->formatStateUsing(fn (?string $v) => match ($v) {
                        'done' => 'ناجحة',
                        'pending' => 'معلّقة',
                        'failed' => 'فاشلة',
                        'banned' => 'محظورة',
                        default => $v ?? '—',
                    })
                    ->color(fn (?string $v) => match ($v) {
                        'done' => 'success',
                        'pending' => 'warning',
                        'failed' => 'danger',
                        default => 'gray',
                    }),
                Tables\Columns\IconColumn::make('refunded')
                    ->label('مستردة')
                    ->boolean()
                    ->toggleable(),
                Tables\Columns\TextColumn::make('transid')
                    ->label('مرجع العملية')
                    ->searchable()
                    ->copyable()
                    ->toggleable(isToggledHiddenByDefault: true),
                Tables\Columns\TextColumn::make('provider_ref_id')
                    ->label('مرجع المزود')
                    ->searchable()
                    ->toggleable(isToggledHiddenByDefault: true),
                Tables\Columns\TextColumn::make('result_desc')
                    ->label('رد المزود')
                    ->limit(40)
                    ->tooltip(fn (TopupOrder $r) => $r->result_desc)
                    ->toggleable(isToggledHiddenByDefault: true),
                Tables\Columns\TextColumn::make('created_at')
                    ->label('التاريخ')
                    ->dateTime('Y-m-d H:i')
                    ->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('status')
                    ->label('الحالة')
                    ->options([
                        'done' => 'ناجحة',
                        'pending' => 'معلّقة',
                        'failed' => 'فاشلة',
                        'banned' => 'محظورة',
                    ]),
                Tables\Filters\SelectFilter::make('service_code')
                    ->label('الخدمة')
                    ->options(fn () => \App\Models\TopupServiceSetting::pluck('name_ar', 'code')->toArray()),
                Tables\Filters\SelectFilter::make('account')
                    ->label('البوابة')
                    ->options(['south' => 'الجنوب', 'north' => 'الشمال']),
                Tables\Filters\SelectFilter::make('user_type')
                    ->label('نوع الحساب')
                    ->options(['client' => 'عميل', 'network_owner' => 'صاحب شبكة', 'pos' => 'نقطة بيع', 'distributor' => 'موزع'])
                    ->query(fn (Builder $q, array $data) => $q->when(
                        $data['value'] ?? null,
                        fn (Builder $qq, $v) => $qq->whereHas('user', fn (Builder $u) => $u->where('type', $v))
                    )),
                Tables\Filters\SelectFilter::make('region')
                    ->label('منطقة العميل')
                    ->options(['south' => 'الجنوب', 'north' => 'الشمال'])
                    ->query(fn (Builder $q, array $data) => $q->when(
                        $data['value'] ?? null,
                        fn (Builder $qq, $v) => $qq->whereHas('user', fn (Builder $u) => $u->where('region_type', $v))
                    )),
                Tables\Filters\Filter::make('created_at')
                    ->label('الفترة')
                    ->form([
                        Forms\Components\DatePicker::make('from')->label('من'),
                        Forms\Components\DatePicker::make('until')->label('إلى'),
                    ])
                    ->query(fn (Builder $q, array $data) => $q
                        ->when($data['from'] ?? null, fn (Builder $qq, $d) => $qq->whereDate('created_at', '>=', $d))
                        ->when($data['until'] ?? null, fn (Builder $qq, $d) => $qq->whereDate('created_at', '<=', $d))),
            ])
            ->defaultSort('created_at', 'desc');
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListTopupOrders::route('/'),
        ];
    }
}
