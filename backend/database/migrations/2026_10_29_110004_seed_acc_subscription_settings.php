<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Admin-editable accounting-subscription knobs (ACC-11, PLAN §6.2),
     * readable via AppSetting::get() and editable from the existing
     * AppSetting Filament resource — no new settings UI needed.
     * enforce ships '0' (allow-all) until launch verification.
     */
    public function up(): void
    {
        $settings = [
            [
                'key' => 'acc.trial_days',
                'value' => '30',
                'type' => 'integer',
                'description' => 'مدة التجربة المجانية لقسم المحاسبة (بالأيام)',
                'is_public' => false,
            ],
            [
                'key' => 'acc.enforce',
                // '1' = entitlement gates active, '0' = allow-all
                // (default until launch). Flip from the admin panel.
                'value' => '0',
                'type' => 'boolean',
                'description' => 'تفعيل بوابات الاشتراك في قسم المحاسبة',
                'is_public' => false,
            ],
            [
                'key' => 'acc.free_features',
                // Billing stays free so an expired tenant can always
                // reach the plans screen and pay.
                'value' => json_encode([
                    'acc.module',
                    'acc.dashboard',
                    'acc.billing',
                ]),
                'type' => 'json',
                'description' => 'الميزات المجانية لقسم المحاسبة بعد انتهاء التجربة',
                'is_public' => false,
            ],
            [
                'key' => 'acc.pricing_note',
                'value' => '',
                'type' => 'string',
                'description' => 'ملاحظة تُعرض أعلى شاشة باقات المحاسبة (أسعار/تواصل)',
                'is_public' => false,
            ],
            [
                'key' => 'acc.trial_is_paid',
                'value' => '0',
                'type' => 'boolean',
                'description' => 'التجربة مجانية (0) أو مدفوعة رمزياً (1)',
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
            'acc.trial_days',
            'acc.enforce',
            'acc.free_features',
            'acc.pricing_note',
            'acc.trial_is_paid',
        ])->delete();
    }
};
