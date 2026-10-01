<?php

namespace App\Filament\Resources;

use App\Filament\Resources\SentNotificationResource\Pages;
use App\Models\SentNotification;
use Filament\Forms;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\KeyValue;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class SentNotificationResource extends Resource
{
    protected static ?string $model = SentNotification::class;
    protected static ?int $navigationSort = 1;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-paper-airplane'; }
    public static function getNavigationLabel(): string { return 'إرسال إشعار'; }
    public static function getNavigationGroup(): ?string { return 'الإشعارات'; }
    public static function getModelLabel(): string { return 'إشعار'; }
    public static function getPluralModelLabel(): string { return 'الإشعارات المرسلة'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            TextInput::make('title')
                ->label('عنوان الإشعار')
                ->required()
                ->maxLength(255),

            Textarea::make('body')
                ->label('نص / جسم الإشعار')
                ->required()
                ->rows(4),

            FileUpload::make('image')
                ->label('صورة الإشعار (Large Icon / Image URL)')
                ->image()
                ->disk('public')
                ->directory('notification_images')
                ->nullable(),

            Select::make('target')
                ->label('تطبيق المستهدفين')
                ->options([
                    'customer_app'      => 'تطبيق العملاء',
                    'network_owner_app' => 'تطبيق أصحاب الشبكات',
                    'all'               => 'الكل',
                ])
                ->required()
                ->default('customer_app'),

            KeyValue::make('payload')
                ->label('البيانات الإضافية للتوجيه (Payload Extras / Deep Link Data)')
                ->keyLabel('المفتاح')
                ->valueLabel('القيمة')
                ->nullable()
                ->helperText('مثال: screen -> network_detail, network_id -> 12'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('title')->label('العنوان')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('body')->label('النص')->limit(50),
                Tables\Columns\TextColumn::make('target')
                    ->label('التطبيق')
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'customer_app'      => 'تطبيق العملاء',
                        'network_owner_app' => 'تطبيق أصحاب الشبكات',
                        default             => 'الكل',
                    }),
                Tables\Columns\ImageColumn::make('image_url')->label('الصورة'),
                Tables\Columns\TextColumn::make('recipients_count')->label('عدد المستلمين'),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإرسال')->dateTime()->sortable(),
            ])
            ->filters([])
            ->actions([
                \Filament\Actions\ViewAction::make()->label('عرض'),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListSentNotifications::route('/'),
            'create' => Pages\CreateSentNotification::route('/create'),
            'view'   => Pages\ViewSentNotification::route('/{record}'),
        ];
    }
}
