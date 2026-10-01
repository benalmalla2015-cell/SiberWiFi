<?php

namespace App\Helpers;

use App\Models\MaintenanceMode;
use App\Models\NetworkOwner;
use App\Models\SupportTicket;
use App\Models\User;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;

class PermissionHelper
{
    /**
     * Map of permission names to Arabic labels.
     *
     * @var array<string, string>
     */
    public static array $PERMISSIONS = [
        // Users
        'view_users'   => 'عرض المستخدمين',
        'add_users'    => 'إضافة المستخدمين',
        'edit_users'   => 'تعديل المستخدمين',
        'delete_users' => 'حذف المستخدمين',

        // Network owners
        'view_network_owners'   => 'عرض أصحاب الشبكات',
        'add_network_owners'    => 'إضافة أصحاب الشبكات',
        'edit_network_owners'   => 'تعديل أصحاب الشبكات',
        'delete_network_owners' => 'حذف أصحاب الشبكات',

        // Roles
        'view_roles'   => 'عرض الأدوار',
        'add_roles'    => 'إضافة الأدوار',
        'edit_roles'   => 'تعديل الأدوار',
        'delete_roles' => 'حذف الأدوار',

        // Permissions
        'view_permissions'   => 'عرض الصلاحيات',
        'add_permissions'    => 'إضافة الصلاحيات',
        'edit_permissions'   => 'تعديل الصلاحيات',
        'delete_permissions' => 'حذف الصلاحيات',

        // Wildcard / global actions
        'view_all'  => 'عرض الكل',
        'add_all'   => 'إضافة الكل',
        'edit_all'  => 'تعديل الكل',
        'delete_all' => 'حذف الكل',
        'all'       => 'جميع الصلاحيات',
    ];

    /**
     * Return all defined permissions as [name => Arabic label].
     *
     * @return array<string, string>
     */
    public static function allPermissions(): array
    {
        return static::$PERMISSIONS;
    }

    /**
     * Return the Arabic label for a permission, or null if unknown.
     */
    public static function label(string $permission): ?string
    {
        return static::$PERMISSIONS[$permission] ?? null;
    }

    /**
     * Map a model class or instance to a resource slug used in permission names.
     */
    public static function resourceSlugForModel(mixed $model): ?string
    {
        if ($model === null || is_array($model) || is_callable($model) || is_resource($model)) {
            return null;
        }

        $class = is_object($model) ? get_class($model) : (string) $model;

        return match ($class) {
            User::class              => 'users',
            NetworkOwner::class      => 'network_owners',
            Role::class              => 'roles',
            Permission::class        => 'permissions',
            SupportTicket::class    => 'support_tickets',
            MaintenanceMode::class => 'maintenance_modes',
            default                  => null,
        };
    }

    /**
     * Map a Filament/Eloquent ability name to a CRUD action slug.
     */
    public static function actionForAbility(string $ability): ?string
    {
        return match ($ability) {
            'viewAny', 'view' => 'view',
            'create'          => 'add',
            'update',
            'reorder',
            'replicate',
            'restore'         => 'edit',
            'delete',
            'deleteAny',
            'forceDelete'     => 'delete',
            default           => null,
        };
    }
}
