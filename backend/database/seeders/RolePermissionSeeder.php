<?php

namespace Database\Seeders;

use App\Helpers\PermissionHelper;
use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;

class RolePermissionSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Run the role and permission seeds.
     */
    public function run(): void
    {
        // Ensure all defined permissions exist.
        $permissionNames = PermissionHelper::allPermissions();
        foreach ($permissionNames as $name) {
            Permission::firstOrCreate(
                ['name' => $name, 'guard_name' => 'web'],
                ['name' => $name, 'guard_name' => 'web']
            );
        }

        // Create the super-admin role.
        $superAdmin = Role::firstOrCreate(
            ['name' => 'super-admin', 'guard_name' => 'web'],
            ['name' => 'super-admin', 'guard_name' => 'web']
        );

        // Give the role every permission.
        $allPermissions = Permission::where('guard_name', 'web')->get();
        $superAdmin->syncPermissions($allPermissions);

        // Assign to the primary admin account if it exists.
        $admin = User::where('email', 'admin@saiberwifi.net')->first();

        if ($admin) {
            $admin->assignRole($superAdmin);
            $admin->syncPermissions($allPermissions);
        }
    }
}
