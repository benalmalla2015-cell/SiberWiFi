<?php

namespace App\Filament\Resources;

use App\Filament\Resources\AccPlanResource\Pages;
use App\Models\AccPlan;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

/**
 * Accounting subscription plans — mirrors MikrotikPlanResource,
 * feature keys mirrored from AccBillingController::FEATURE_KEYS.
 */
class AccPlanResource extends Resource
{
    protected static ?string $model = AccPlan::class;
    protected static ?int $navigationSort = 15;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-calculator'; }
    public static function getNavigationLabel(): string { return 'خطط المحاسبة'; }
    public static function getNavigationGroup(): ?string { return 'المحاسبة'; }

    public static function featureLabels(): array
    {
        return [
            'acc.module' => 'النظام المحاسبي (الوصول)',
            'acc.dashboard' => 'لوحة المحاسبة',
            'acc.inventory' => 'المخزون',
            'acc.categories' => 'الأصناف والفئات',
            'acc.sales' => 'المبيعات',
            'acc.pos_points' => 'نقاط البيع',
            'acc.pos_orders' => 'طلبات نقاط البيع',
            'acc.agents' => 'الوكلاء والموظفون',
            'acc.network_devices' => 'أجهزة الشبكة',
            'acc.collections' => 'التحصيلات',
            'acc.debts' => 'الديون',
            'acc.balances' => 'الأرصدة',
            'acc.expenses' => 'المصروفات',
            'acc.purchases' => 'المشتريات',
            'acc.returns' => 'المرتجعات',
            'acc.damaged' => 'التالف',
            'acc.discount_tiers' => 'شرائح الخصم',
            'acc.cash_boxes' => 'الصناديق النقدية',
            'acc.journal' => 'قيود اليومية',
            'acc.reports' => 'التقارير',
            'acc.pos_analysis' => 'تحليلات نقاط البيع',
            'acc.audit_log' => 'سجل التدقيق',
            'acc.sync_center' => 'مركز المزامنة',
            'acc.backup' => 'النسخ الاحتياطي',
            'acc.settings' => 'الإعدادات',
            'acc.billing' => 'الفوترة والاشتراك',
            'acc.distributor' => 'تطبيق الموزع',
            'acc.pos_app' => 'تطبيق الكاشير',
        ];
    }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Grid::make(2)->schema([
                Forms\Components\TextInput::make('name')
                    ->label('اسم الخطة')->required()->maxLength(255),
                Forms\Components\TextInput::make('price')
                    ->label('السعر')->numeric()->required()
                    ->suffix('ر.ي'),
            ]),
            Grid::make(3)->schema([
                Forms\Components\TextInput::make('duration_days')
                    ->label('المدة (أيام)')->numeric()->required(),
                Forms\Components\TextInput::make('sort_order')
                    ->label('الترتيب')->numeric()->default(0),
                Forms\Components\Toggle::make('is_active')
                    ->label('مفعّلة')->default(true),
            ]),
            Forms\Components\Textarea::make('description')
                ->label('الوصف')->rows(2)->columnSpanFull(),
            Forms\Components\CheckboxList::make('features')
                ->label('الميزات المشمولة في الخطة')
                ->options(self::featureLabels())
                ->columns(3)
                ->default(array_keys(self::featureLabels()))
                ->helperText('الخطة الواحدة تغطي المالك وكل وكلائه — يمكن تقييد الميزات هنا'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('name')->label('الخطة')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('price')->label('السعر')->money('YER')->sortable(),
                Tables\Columns\TextColumn::make('duration_days')->label('المدة')->suffix(' يوم')->sortable(),
                Tables\Columns\TextColumn::make('features')
                    ->label('الميزات')
                    ->getStateUsing(fn ($record) => count($record->features ?? []) . ' ميزة'),
                Tables\Columns\IconColumn::make('is_active')->label('مفعّلة')->boolean(),
                Tables\Columns\TextColumn::make('subscriptions_count')
                    ->counts('subscriptions')->label('الاشتراكات'),
            ])
            ->filters([
                Tables\Filters\TernaryFilter::make('is_active')->label('مفعّلة'),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('sort_order', 'asc')
            ->paginated([25, 50]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListAccPlans::route('/'),
            'create' => Pages\CreateAccPlan::route('/create'),
            'edit' => Pages\EditAccPlan::route('/{record}/edit'),
        ];
    }
}
