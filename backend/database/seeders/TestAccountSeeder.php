<?php

namespace Database\Seeders;

use App\Models\Directorate;
use App\Models\Network;
use App\Models\NetworkOwner;
use App\Models\Region;
use App\Models\SubDirectorate;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class TestAccountSeeder extends Seeder
{
    public function run(): void
    {
        // Remove previously soft-deleted demo accounts so their unique
        // account_number / referral_code values can be reused safely.
        User::withTrashed()
            ->whereNotNull('deleted_at')
            ->where(function ($q) {
                $q->whereIn('account_number', [
                    'SW-TEST-CLI-001', 'SW-TEST-OWN-001', 'SW-TEST-CLI-003',
                ])->orWhereIn('referral_code', [
                    'TESTCLI001', 'TESTOWN001', 'TESTCLI003',
                ]);
            })
            ->get()
            ->each->forceDelete();

        $region = Region::firstOrCreate(
            ['name' => 'أمانة العاصمة'],
            ['type' => 'north', 'is_active' => true],
        );

        $directorate = Directorate::firstOrCreate(
            ['region_id' => $region->id, 'name' => 'التحرير'],
            ['name_en' => 'Al Tahrir', 'is_active' => true],
        );

        $subDirectorate = SubDirectorate::firstOrCreate(
            ['directorate_id' => $directorate->id, 'name' => 'الرباط'],
            ['name_en' => 'Ar Rabat', 'is_active' => true],
        );

        User::updateOrCreate(
            ['phone' => '700000001'],
            [
                'name'               => 'عميل تجريبي',
                'password'           => Hash::make('123456'),
                'type'               => 'client',
                'region_type'        => 'north',
                'region_id'          => $region->id,
                'directorate_id'     => $directorate->id,
                'sub_directorate_id' => $subDirectorate->id,
                'account_number'     => 'SW-TEST-CLI-001',
                'referral_code'      => 'TESTCLI001',
                'balance'            => 0,
                'available_balance'  => 0,
                'frozen_balance'     => 0,
                'currency'           => 'YER',
                'is_active'          => true,
                'is_verified'        => true,
            ]
        );

        User::updateOrCreate(
            ['phone' => '700000003'],
            [
                'name'               => 'حساب حذف تجريبي ثان',
                'password'           => Hash::make('123456'),
                'type'               => 'client',
                'region_type'        => 'north',
                'region_id'          => $region->id,
                'directorate_id'     => $directorate->id,
                'sub_directorate_id' => $subDirectorate->id,
                'account_number'     => 'SW-TEST-CLI-003',
                'referral_code'      => 'TESTCLI003',
                'balance'            => 0,
                'available_balance'  => 0,
                'frozen_balance'     => 0,
                'currency'           => 'YER',
                'is_active'          => true,
                'is_verified'        => true,
            ]
        );

        $owner = User::updateOrCreate(
            ['phone' => '700000002'],
            [
                'name'               => 'صاحب شبكة تجريبي',
                'password'           => Hash::make('123456'),
                'type'               => 'network_owner',
                'region_type'        => 'north',
                'region_id'          => $region->id,
                'directorate_id'     => $directorate->id,
                'sub_directorate_id' => $subDirectorate->id,
                'account_number'     => 'SW-TEST-OWN-001',
                'referral_code'      => 'TESTOWN001',
                'balance'            => 0,
                'available_balance'  => 0,
                'frozen_balance'     => 0,
                'currency'           => 'YER',
                'is_active'          => true,
                'is_verified'        => true,
            ]
        );

        NetworkOwner::updateOrCreate(
            ['user_id' => $owner->id],
            ['business_name' => 'شبكة تجريبية', 'is_approved' => true],
        );

        Network::updateOrCreate(
            ['user_id' => $owner->id, 'name' => 'شبكة تجريبية'],
            [
                'region_id'          => $region->id,
                'directorate_id'     => $directorate->id,
                'sub_directorate_id' => $subDirectorate->id,
                'slug'               => 'test-network-' . Str::random(6),
                'status'             => 'active',
                'description'        => 'شبكة تجريبية لاختبار حذف الحساب',
            ]
        );
    }
}
