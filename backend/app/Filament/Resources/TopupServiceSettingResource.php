<?php

namespace App\Filament\Resources;

use App\Filament\Resources\TopupServiceSettingResource\Pages;
use App\Models\TopupServiceSetting;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class TopupServiceSettingResource extends Resource
{
    protected static ?string $model = TopupServiceSetting::class;
    protected static ?int $navigationSort = 4;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-bolt'; }
    public static function getNavigationLabel(): string { return 'خدمات الشحن الفوري'; }
    public static function getNavigationGroup(): ?string { return 'الإعدادات'; }
    public static function getModelLabel(): string { return 'خدمة'; }
    public static function getPluralModelLabel(): string { return 'خدمات الشحن الفوري'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\TextInput::make('name_ar')
                ->label('اسم الخدمة')
                ->required(),
            Forms\Components\TextInput::make('code')
                ->label('الرمز')
                ->disabled()
                ->dehydrated(),
            Forms\Components\Select::make('category')
                ->label('الفئة')
                ->options([
                    'mobile' => 'شحن هواتف',
                    'landline' => 'هاتف ثابت / ADSL',
                    'utility' => 'كهرباء وماء',
                    'game' => 'ألعاب وبطاقات',
                    'wholesale' => 'شحن جملة',
                ])
                ->required(),
            Forms\Components\Select::make('account')
                ->label('حساب المزود')
                ->options(['south' => 'جنوب', 'north' => 'شمال'])
                ->required(),
            Forms\Components\Select::make('fee_type')
                ->label('نوع العمولة')
                ->options([
                    'none' => 'بدون عمولة',
                    'percent' => 'نسبة مئوية %',
                    'fixed' => 'مبلغ ثابت',
                ])
                ->default('none')
                ->live()
                ->required(),
            Forms\Components\TextInput::make('fee_value')
                ->label('قيمة العمولة')
                ->numeric()
                ->default(0)
                ->minValue(0)
                ->visible(fn (Forms\Get $get) => $get('fee_type') !== 'none')
                ->suffix(fn (Forms\Get $get) => $get('fee_type') === 'percent' ? '%' : 'ر.ي'),
            Forms\Components\TextInput::make('sort_order')
                ->label('الترتيب')
                ->numeric()
                ->default(0),
            Forms\Components\Repeater::make('packages')
                ->label('الباقات وفئات فوري')
                ->helperText('بطاقات تظهر في التطبيق. «السعر» هو ما يُدفع دائماً؛ «التفعيل» يحدد طريقة التنفيذ لدى المزود.')
                ->schema([
                    Forms\Components\TextInput::make('name')->label('الاسم')->required(),
                    Forms\Components\TextInput::make('code')->label('الكود (معرّف فريد)')->required(),
                    Forms\Components\TextInput::make('price')->label('السعر')->numeric()->required(),
                    Forms\Components\TextInput::make('group')
                        ->label('المجموعة')
                        ->placeholder('باقات سوا / فوري — فئات / …')
                        ->helperText('بطاقات نفس المجموعة تُعرض معاً'),
                    Forms\Components\Select::make('network')
                        ->label('البوابة')
                        ->options(['both' => 'الكل', 'south' => 'جنوب فقط', 'north' => 'شمال فقط'])
                        ->default('both'),
                    Forms\Components\Select::make('paytype')
                        ->label('نوع الخط')
                        ->options(['both' => 'الكل', 'prepaid' => 'مسبق الدفع', 'postpaid' => 'فوترة'])
                        ->default('both'),
                    Forms\Components\Select::make('activation')
                        ->label('التفعيل')
                        ->options([
                            'amount' => 'سداد مبلغ (السعر يصل رصيداً)',
                            'offeryem' => 'تفعيل عرض يمن (offerkey)',
                            'billoffer' => 'تفعيل عرض يمن (offerid)',
                            'mtnoffer' => 'باقة MTN (num=الكود)',
                            'sabaoffer' => 'باقة سبأفون (num=الكود)',
                        ])
                        ->default('amount'),
                    Forms\Components\TextInput::make('data')->label('البيانات (2GB)'),
                    Forms\Components\TextInput::make('days')->label('المدة بالأيام'),
                    Forms\Components\TextInput::make('minutes')->label('الدقائق'),
                    Forms\Components\TextInput::make('sms')->label('الرسائل'),
                    Forms\Components\TextInput::make('note')->label('ملاحظة'),
                    Forms\Components\TextInput::make('params')->label('معاملات إضافية (JSON)')->placeholder('{"type":"adsl"}'),
                ])
                ->columns(3)
                ->collapsed()
                ->itemLabel(fn (array $state): ?string => $state['name'] ?? null),
            Forms\Components\KeyValue::make('meta.places')
                ->label('المناطق (معرّف المنطقة ⇒ اسمها)')
                ->keyLabel('معرّف المنطقة (placeid)')
                ->valueLabel('اسم المنطقة')
                ->helperText('تظهر للعميل كقائمة منسدلة في خدمتي الكهرباء والماء — انسخها من لوحة المزود.')
                ->visible(fn (Forms\Get $get) => $get('category') === 'utility'),
            Forms\Components\Toggle::make('is_active')->label('مفعّلة')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('name_ar')->label('الخدمة')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('category')
                    ->label('الفئة')
                    ->badge()
                    ->formatStateUsing(fn (string $state) => match ($state) {
                        'mobile' => 'شحن هواتف',
                        'landline' => 'ثابت/ADSL',
                        'utility' => 'كهرباء/ماء',
                        'game' => 'ألعاب',
                        'wholesale' => 'جملة',
                        default => $state,
                    }),
                Tables\Columns\TextColumn::make('account')->label('الحساب')->badge(),
                Tables\Columns\TextColumn::make('fee_type')
                    ->label('العمولة')
                    ->formatStateUsing(fn (TopupServiceSetting $r) => match ($r->fee_type) {
                        'percent' => $r->fee_value . '%',
                        'fixed' => $r->fee_value . ' ر.ي',
                        default => 'بدون',
                    }),
                Tables\Columns\IconColumn::make('is_active')->label('مفعّلة')->boolean(),
                Tables\Columns\TextColumn::make('updated_at')->label('آخر تحديث')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('category')
                    ->label('الفئة')
                    ->options([
                        'mobile' => 'شحن هواتف',
                        'landline' => 'ثابت/ADSL',
                        'utility' => 'كهرباء/ماء',
                        'game' => 'ألعاب',
                        'wholesale' => 'جملة',
                    ]),
                Tables\Filters\TernaryFilter::make('is_active')->label('مفعّلة'),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
            ])
            ->defaultSort('sort_order')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListTopupServiceSettings::route('/'),
            'edit' => Pages\EditTopupServiceSetting::route('/{record}/edit'),
        ];
    }
}
