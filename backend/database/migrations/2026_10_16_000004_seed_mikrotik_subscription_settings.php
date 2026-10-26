<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Admin-editable subscription knobs, readable via
     * AppSetting::get() everywhere and editable from the existing
     * AppSetting Filament resource — no new settings UI needed.
     */
    public function up(): void
    {
        $settings = [
            [
                'key' => 'mikrotik.trial_days',
                'value' => '14',
                'type' => 'integer',
                'description' => 'مدة التجربة المجانية لتطبيق إدارة المايكروتك (بالأيام)',
                'is_public' => false,
            ],
            [
                'key' => 'mikrotik.enforce',
                // '1' = entitlement gates active, '0' = allow-all (default
                // until launch). Flip from the admin panel.
                'value' => '0',
                'type' => 'boolean',
                'description' => 'تفعيل بوابات الاشتراك في تطبيق المايكروتك',
                'is_public' => false,
            ],
            [
                'key' => 'mikrotik.free_features',
                'value' => json_encode([
                    'mikrotik.connection',
                    'mikrotik.monitoring',
                    'mikrotik.hotspot_users',
                ]),
                'type' => 'json',
                'description' => 'الميزات المجانية لتطبيق المايكروتك بعد انتهاء التجربة',
                'is_public' => false,
            ],
        ];

        foreach ($settings as $s) {
            DB::table('app_settings')->updateOrInsert(
                ['key' => $s['key']],
                $s + ['created_at' => now(), 'updated_at' => now()]
            );
        }
    }

    public function down(): void
    {
        DB::table('app_settings')->whereIn('key', [
            'mikrotik.trial_days',
            'mikrotik.enforce',
            'mikrotik.free_features',
        ])->delete();
    }
};
