<?php

namespace Database\Seeders;

use App\Models\AppSetting;
use App\Models\CashbackSetting;
use App\Models\CommissionSetting;
use App\Models\Directorate;
use App\Models\Region;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class AdminSeeder extends Seeder
{
    public function run(): void
    {
        // ─── Super Admin ───────────────────────────────────────────
        $admin = User::updateOrCreate(
            ['phone' => '777000001'],
            [
                'name'           => 'مشرف سايبر',
                'email'          => 'admin@saiberwifi.net',
                'password'       => bcrypt('Admin@2025!'),
                'type'           => 'admin',
                'region_type'    => 'north',
                'account_number' => 'SW00000001',
                'referral_code'  => 'ADMIN001',
                'is_active'      => true,
                'is_verified'    => true,
            ]
        );
        $this->command->info("Admin created: {$admin->email} / Admin@2025!");

        // ─── Regions ───────────────────────────────────────────────
        $north = Region::updateOrCreate(['type' => 'north'], [
            'name'     => 'الشمال',
            'name_en'  => 'North Yemen',
            'currency' => 'YER_OLD',
            'is_active' => true,
        ]);

        $south = Region::updateOrCreate(['type' => 'south'], [
            'name'     => 'الجنوب',
            'name_en'  => 'South Yemen',
            'currency' => 'YER_NEW',
            'is_active' => true,
        ]);

        // ─── Directorates (North) ───────────────────────────────────
        $northDirs = ['صنعاء', 'عمران', 'صعدة', 'حجة', 'المحويت', 'ذمار', 'إب', 'البيضاء', 'مأرب', 'الجوف', 'شبوة', 'الحديدة', 'ريمة', 'حضرموت', 'المهرة'];
        foreach ($northDirs as $dir) {
            Directorate::updateOrCreate(['name' => $dir, 'region_id' => $north->id], ['name_en' => $dir, 'is_active' => true]);
        }

        // ─── Directorates (South) ───────────────────────────────────
        $southDirs = ['عدن', 'لحج', 'أبين', 'الضالع', 'تعز', 'المكلا', 'سقطرى'];
        foreach ($southDirs as $dir) {
            Directorate::updateOrCreate(['name' => $dir, 'region_id' => $south->id], ['name_en' => $dir, 'is_active' => true]);
        }

        // ─── Commission settings ────────────────────────────────────
        CommissionSetting::updateOrCreate(['type' => 'app'], [
            'name'       => 'عمولة التطبيق',
            'percentage' => 5.00,
            'is_active'  => true,
        ]);
        CommissionSetting::updateOrCreate(['type' => 'referral'], [
            'name'       => 'عمولة الإحالة',
            'percentage' => 2.00,
            'is_active'  => true,
        ]);
        CommissionSetting::updateOrCreate(['type' => 'charging_point'], [
            'name'       => 'عمولة نقطة الشحن',
            'percentage' => 1.00,
            'is_active'  => true,
        ]);

        // ─── Cashback settings ──────────────────────────────────────
        CashbackSetting::updateOrCreate(['is_global' => true], [
            'name'               => 'كاشباك اشتري 10',
            'buy_count'          => 10,
            'cashback_percentage' => 10.00,
            'is_active'          => true,
        ]);

        // ─── App settings ───────────────────────────────────────────
        $settings = [
            ['key' => 'app_name',         'value' => 'سايبر WiFi',        'type' => 'string'],
            ['key' => 'app_version',       'value' => '1.0.0',             'type' => 'string'],
            ['key' => 'min_payout_amount', 'value' => '1000',              'type' => 'integer'],
            ['key' => 'support_phone',     'value' => '+967777000000',      'type' => 'string'],
            ['key' => 'support_whatsapp',  'value' => '+967777000000',      'type' => 'string'],
            ['key' => 'maintenance_mode',  'value' => '0',                 'type' => 'boolean'],
            ['key' => 'terms_url',         'value' => 'https://saiberwifi.net/terms', 'type' => 'string'],
            ['key' => 'privacy_url',       'value' => 'https://saiberwifi.net/privacy', 'type' => 'string'],
        ];
        foreach ($settings as $s) {
            AppSetting::updateOrCreate(['key' => $s['key']], $s);
        }

        $this->command->info('Seeding complete: ' . Region::count() . ' regions, ' . Directorate::count() . ' directorates.');
    }
}
