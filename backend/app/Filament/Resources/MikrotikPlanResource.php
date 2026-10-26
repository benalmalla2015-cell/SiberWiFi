<?php

namespace App\Filament\Resources;

use App\Filament\Resources\MikrotikPlanResource\Pages;
use App\Models\MikrotikPlan;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class MikrotikPlanResource extends Resource
{
    protected static ?string $model = MikrotikPlan::class;
    protected static ?int $navigationSort = 12;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-credit-card'; }
    public static function getNavigationLabel(): string { return 'خطط اشتراك MikroTik'; }
    public static function getNavigationGroup(): ?string { return 'الشبكات'; }

    public static function featureLabels(): array
    {
        return [
            'mikrotik.connection' => 'الاتصال بالراوتر',
            'mikrotik.monitoring' => 'المراقبة والأدوات',
            'mikrotik.hotspot_users' => 'مستخدمو Hotspot',
            'mikrotik.voucher_cards' => 'توليد الكروت',
            'mikrotik.card_templates' => 'قوالب وطباعة الكروت',
            'mikrotik.pppoe' => 'مستخدمو PPPoE',
            'mikrotik.user_manager' => 'User Manager',
            'mikrotik.profiles' => 'الباقات والبروفايلات',
            'mikrotik.queues' => 'طوابير السرعة',
            'mikrotik.firewall' => 'الفايروول والحماية',
            'mikrotik.nat' => 'قواعد NAT',
            'mikrotik.network_tools' => 'أدوات الشبكة المتقدمة',
            'mikrotik.diagnostics' => 'أدوات التشخيص',
            'mikrotik.system_admin' => 'إدارة النظام',
            'mikrotik.backup' => 'النسخ الاحتياطي',
            'mikrotik.hotspot_pages' => 'صفحات الهوتسبوت',
            'mikrotik.telegram' => 'تنبيهات Telegram',
            'mikrotik.remote_access' => 'الوصول عن بُعد',
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
                ->helperText('كل الخطط المدفوعة تفتح كل الميزات عادة — يمكن تقييدها هنا'),
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
                    ->getStateUsing(fn($r) => count($r->features ?? []) . ' ميزة'),
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
            'index' => Pages\ListMikrotikPlans::route('/'),
            'create' => Pages\CreateMikrotikPlan::route('/create'),
            'edit' => Pages\EditMikrotikPlan::route('/{record}/edit'),
        ];
    }
}
