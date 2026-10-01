<?php

namespace App\Filament\Resources;

use App\Filament\Resources\PermissionResource\Pages;
use Filament\Forms;
use Filament\Notifications\Notification;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;
use Spatie\Permission\Models\Permission;

class PermissionResource extends Resource
{
    protected static ?string $model = Permission::class;
    protected static ?int $navigationSort = 4;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-key'; }
    public static function getNavigationLabel(): string { return 'الصلاحيات'; }
    public static function getNavigationGroup(): ?string { return 'إدارة المستخدمين'; }

    public static function getPermissionInterfaces(): array
    {
        return [
            'dashboard'            => 'لوحة التحكم',
            'support_tickets'      => 'طلبات الدعم الفني',
            'send_notification'    => 'إرسال إشعار',
            'maintenance_modes'    => 'وضع الصيانة',
            'users'                => 'المستخدمون',
            'employees'            => 'الموظفون',
            'roles'                => 'الأدوار',
            'permissions'          => 'الصلاحيات',
            'advertisements'       => 'الإعلانات',
            'app_settings'         => 'إعدادات التطبيق',
            'bank_accounts'        => 'الحسابات البنكية',
            'card_categories'      => 'فئات البطاقات',
            'cashback_settings'    => 'إعدادات الكاش باك',
            'charging_points'      => 'نقاط الشحن',
            'commission_settings'  => 'إعدادات العمولات',
            'daily_offers'         => 'العروض اليومية',
            'directorates'         => 'المديريات',
            'network_owners'       => 'أصحاب الشبكات',
            'networks'             => 'الشبكات',
            'payout_requests'      => 'طلبات السحب',
            'referrals'            => 'الإحالات',
            'regions'              => 'المناطق',
            'reports'              => 'البلاغات',
            'transactions'         => 'المعاملات',
            'wallet_logs'          => 'سجلات المحفظة',
        ];
    }

    public static function formatPermissionName(string $name): string
    {
        $interfaces = static::getPermissionInterfaces();
        $actions = static::getPermissionActions();

        // Format used by the custom permission creation UI: interface.action
        if (str_contains($name, '.')) {
            [$interface, $action] = explode('.', $name, 2);
            $interfaceLabel = $interfaces[$interface] ?? $interface;
            $actionLabel = $actions[$action] ?? $action;
            return "{$interfaceLabel} - {$actionLabel}";
        }

        // Format used by the access gate: action_interface
        if (str_contains($name, '_')) {
            [$action, $interface] = explode('_', $name, 2);
            $interfaceLabel = $interfaces[$interface] ?? $interface;
            $actionLabel = $actions[$action] ?? $action;
            return "{$interfaceLabel} - {$actionLabel}";
        }

        return $interfaces[$name] ?? $name;
    }

    public static function getPermissionActions(): array
    {
        return [
            'view'   => 'عرض',
            'create' => 'إضافة',
            'edit'   => 'تعديل',
            'delete' => 'حذف',
        ];
    }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Section::make()->schema([
                Forms\Components\TextInput::make('name')
                    ->label('اسم الصلاحية')
                    ->required()
                    ->unique(ignoreRecord: true)
                    ->maxLength(255)
                    ->placeholder('مثال: view_users'),
                Forms\Components\TextInput::make('guard_name')
                    ->label('الحارس (Guard)')
                    ->default('web')
                    ->required()
                    ->maxLength(255),
            ])->columns(2),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#')->sortable(),
                Tables\Columns\TextColumn::make('name')
                    ->label('اسم الصلاحية')
                    ->searchable()
                    ->formatStateUsing(fn (string $state): string => static::formatPermissionName($state)),
                Tables\Columns\TextColumn::make('guard_name')->label('الحارس')->badge(),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ الإنشاء')->date()->sortable(),
            ])
            ->filters([])
            ->actions([
                \Filament\Actions\EditAction::make()->label('تعديل'),
                \Filament\Actions\DeleteAction::make()->label('حذف'),
            ])
            ->defaultSort('created_at', 'desc');
    }

    public static function getRelations(): array
    {
        return [];
    }

    public static function getPages(): array
    {
        return [
            'index'  => Pages\ListPermissions::route('/'),
            'create' => Pages\CreatePermission::route('/create'),
            'edit'   => Pages\EditPermission::route('/{record}/edit'),
        ];
    }
}
