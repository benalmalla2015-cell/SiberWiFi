<?php

namespace App\Filament\Resources\PermissionResource\Pages;

use App\Filament\Resources\PermissionResource;
use Filament\Actions;
use Filament\Forms;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ListRecords;
use Spatie\Permission\Models\Permission;

class ListPermissions extends ListRecords
{
    protected static string $resource = PermissionResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Actions\CreateAction::make()->label('إضافة صلاحية'),
            Actions\Action::make('create_custom_permissions')
                ->label('إضافة صلاحيات مخصصة')
                ->icon('heroicon-o-plus-circle')
                ->color('success')
                ->form([
                    Forms\Components\Repeater::make('items')
                        ->label('مجموعات الصلاحيات')
                        ->addActionLabel('إضافة واجهة')
                        ->minItems(1)
                        ->required()
                        ->schema([
                            Forms\Components\Select::make('interface')
                                ->label('الواجهة / القسم')
                                ->options(PermissionResource::getPermissionInterfaces())
                                ->searchable()
                                ->required(),
                            Forms\Components\CheckboxList::make('actions')
                                ->label('العمليات المسموحة')
                                ->options(PermissionResource::getPermissionActions())
                                ->required()
                                ->columns(4),
                        ])
                        ->columns(2),
                ])
                ->action(function (array $data) {
                    $created = 0;
                    foreach ($data['items'] as $item) {
                        $interface = $item['interface'];
                        foreach ($item['actions'] as $action) {
                            $actionSlug = match ($action) {
                                'create' => 'add',
                                default  => $action,
                            };
                            $name = "{$actionSlug}_{$interface}";
                            Permission::firstOrCreate(
                                ['name' => $name, 'guard_name' => 'web'],
                            );
                            $created++;
                        }
                    }

                    Notification::make()
                        ->title("تم إنشاء {$created} صلاحية بنجاح")
                        ->success()
                        ->send();

                    return redirect(static::getResource()::getUrl('index'));
                }),
        ];
    }
}
