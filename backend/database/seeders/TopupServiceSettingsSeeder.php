<?php

namespace Database\Seeders;

use App\Models\TopupServiceSetting;
use Illuminate\Database\Seeder;

class TopupServiceSettingsSeeder extends Seeder
{
    /**
     * Compact package row. Extra keys allowed:
     *   group      — collapsible section title in the app's packages tab
     *   network    — south | north | both (gateway filter)
     *   paytype    — prepaid | postpaid | both (line-type filter)
     *   activation — amount | offeryem | billoffer | mtnoffer | sabaoffer
     *   params     — extra provider params merged into the bill call
     *   days/minutes/sms/data — spec chips rendered under the package name
     *   mode_label — شريحة / دفع مسبق / فوترة …
     */
    private static function pkg(
        string $name,
        string $code,
        float $price,
        string $group,
        array $extra = []
    ): array {
        return compact('name', 'code', 'price', 'group') + $extra;
    }

    public function run(): void
    {
        // ── meta keys ───────────────────────────────────────────────
        // fields        -> dynamic form specs (number/amount/select/text/email)
        // tabs          -> ['rasid','fory','packages','gomla'] tab bar order
        // offers        -> provider endpoint for live subscriber offers
        // query         -> enables the free query button
        // unit_price    -> units × price billing (Sabafon credit)
        // unit_label    -> label for the units field
        // net_ratio     -> delivered-credit estimate (tax inclusive → net)
        // color         -> operator accent color (hex) for the app header
        // places        -> admin-managed {placeid => name} for utilities
        // fory_net      -> فوري فئة list is billed per package.price

        $services = [
            // ── Mobile top-up ──────────────────────────────────────
            ['code' => 'yem', 'name_ar' => 'يمن موبايل', 'category' => 'mobile',
             'provider_endpoint' => 'yem', 'sort_order' => 1,
             'meta' => [
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف'],
                             ['key' => 'paytype', 'type' => 'select', 'label' => 'نوع الخط',
                              'options' => [['v' => 'prepaid', 'l' => 'دفع مسبق'], ['v' => 'postpaid', 'l' => 'فوترة']]]],
                'tabs' => ['rasid', 'fory', 'packages'],
                'offers' => 'queryoffer', 'query' => true,
                'net_ratio' => 0.8264, 'color' => '#7B2FBE',
             ],
             'packages' => [
                // ── فوري — جنوب ──
                ...self::fories('south', [[22.5, 272], [40, 484], [45, 545], [60, 726],
                    [85, 1029], [100, 1210], [125, 1513], [150, 1815], [209, 2529]]),
                // ── فوري — شمال ──
                ...self::fories('north', [[600, 960], [1000, 1600], [1650, 2640],
                    [2500, 4000], [5000, 8000], [10000, 16000]]),
                // ── كتالوج باقات يمن موبايل — أسعار جنوب / شمال لكل بوابة ──
                // (العميل يرى أسعار البوابة المختارة فقط — مثل تبويبَي شمال/جنوب
                //  في تطبيق المزود). السعر الشمالي ≈ الجنوبي ÷ 3.05.
                ...self::dual([
                    // ── EVDO — انترنت شهري ──
                    ['EVDO انترنت شهري — 150 ميجا', 'evdo-150', 400, 'باقات EVDO — انترنت شهري', ['data' => '150MB']],
                    ['EVDO انترنت شهري — 300 ميجا', 'evdo-300', 800, 'باقات EVDO — انترنت شهري', ['data' => '300MB']],
                    ['EVDO انترنت شهري — 450 ميجا', 'evdo-450', 1200, 'باقات EVDO — انترنت شهري', ['data' => '450MB']],
                    ['EVDO انترنت شهري — 700 ميجا', 'evdo-700', 1900, 'باقات EVDO — انترنت شهري', ['data' => '700MB']],
                    ['EVDO انترنت شهري — 1500 ميجا', 'evdo-1500', 3600, 'باقات EVDO — انترنت شهري', ['data' => '1.5GB']],
                    ['EVDO انترنت شهري — 3 جيجا', 'evdo-3g', 6600, 'باقات EVDO — انترنت شهري', ['data' => '3GB']],
                    ['EVDO انترنت شهري — 5 جيجا', 'evdo-5g', 9600, 'باقات EVDO — انترنت شهري', ['data' => '5GB']],
                    // ── انترنت 10 أيام ──
                    ['انترنت 10 أيام — 1 جيجا', 'd10-1g', 1400, 'باقات انترنت 10 أيام', ['data' => '1GB', 'days' => '10']],
                    ['انترنت 10 أيام — 2 جيجا', 'd10-2g', 2600, 'باقات انترنت 10 أيام', ['data' => '2GB', 'days' => '10']],
                    ['انترنت 10 أيام — 4 جيجا', 'd10-4g', 4800, 'باقات انترنت 10 أيام', ['data' => '4GB', 'days' => '10']],
                    ['انترنت 10 أيام — 6 جيجا', 'd10-6g', 6000, 'باقات انترنت 10 أيام', ['data' => '6GB', 'days' => '10']],
                    // ── مزايا فورجي (أسعار مؤكدة: أسبوعية 485 / شهرية 1300 جنوبي) ──
                    ['مزايا فورجي — أسبوعية', '444*03', 485, 'باقات مزايا فورجي', ['days' => '7']],
                    ['مزايا فورجي — شهرية', '444*04', 1300, 'باقات مزايا فورجي', ['days' => '30']],
                    ['مزايا فورجي — ماكس', '444*05', 1350, 'باقات مزايا فورجي', ['days' => '30']],
                    // ── فولتي ──
                    ['فولتي — 24 ساعة', 'volt-24', 200, 'باقات فولتي', ['days' => '1']],
                    ['فولتي — 48 ساعة', 'volt-48', 400, 'باقات فولتي', ['days' => '2']],
                    ['فولتي — أسبوعي', 'volt-w', 1100, 'باقات فولتي', ['days' => '7']],
                    ['فولتي — شهري', 'volt-m', 2200, 'باقات فولتي', ['days' => '30']],
                    ['فولتي — ماكس', 'volt-max', 2600, 'باقات فولتي', ['days' => '30']],
                    // ── تواصل ──
                    ['تواصل — شهري', 'tawasul-m', 2800, 'باقات تواصل', ['days' => '30']],
                    ['تواصل — ماكس', 'tawasul-max', 3000, 'باقات تواصل', ['days' => '30']],
                    // ── باقات 3G ──
                    ['3G — تفعيل خدمة الانترنت', 'g3-act', 100, 'باقات 3G'],
                    ['3G — باقة يومية', 'g3-d', 500, 'باقات 3G', ['days' => '1']],
                    ['3G — باقة أسبوعية', 'g3-w', 1200, 'باقات 3G', ['days' => '7']],
                    ['3G — باقة شهرية', 'g3-m', 2500, 'باقات 3G', ['days' => '30']],
                    // ── رسائل ──
                    ['رسائل — 150 رسالة', 'sms150', 150, 'باقات الرسائل', ['sms' => '150']],
                    ['رسائل — 300 رسالة', 'sms300', 300, 'باقات الرسائل', ['sms' => '300']],
                ]),
                // ── سلفوني (سلفة رصيد — نفس القيمة بالبوابتين) ──
                self::pkg('سلفوني — 50', 'salf-50', 50, 'سلفوني (استلاف رصيد)'),
                self::pkg('سلفوني — 100', 'salf-100', 100, 'سلفوني (استلاف رصيد)'),
                self::pkg('سلفوني — 200', 'salf-200', 200, 'سلفوني (استلاف رصيد)'),
            ]],

            ['code' => 'mtn', 'name_ar' => 'MTN / YOU', 'category' => 'mobile',
             'provider_endpoint' => 'mtn', 'sort_order' => 2,
             'meta' => [
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف'],
                             ['key' => 'type', 'type' => 'select', 'label' => 'نوع الخط',
                              'options' => [['v' => 'prepaid', 'l' => 'مسبق الدفع'], ['v' => 'postpaid', 'l' => 'آجل الدفع']]],
                             ['key' => 'israsid', 'type' => 'select', 'label' => 'نوع الشحن',
                              'options' => [['v' => '0', 'l' => 'شحن عادي'], ['v' => '1', 'l' => 'شحن رصيد']]]],
                'tabs' => ['rasid', 'fory', 'packages'],
                'color' => '#F5B301', 'net_ratio' => 1.0,
             ],
             'packages' => [
                // ── فوري (سعر شامل الضريبة) ──
                ...self::fories('both', [[410, 497], [830, 1004], [1000, 1200], [1250, 1500],
                    [2500, 3000], [5000, 6000], [7500, 9000], [10000, 12000]]),
                // ── سوا ──
                self::pkg('سوا — أسبوعية', 'sawa-w', 1500, 'باقات سوا', ['days' => '7']),
                self::pkg('سوا — شهرية', 'sawa-m', 3000, 'باقات سوا', ['days' => '30']),
                self::pkg('السعر الموحد', 'sawa-flat', 1760, 'باقات سوا'),
                // ── مكس ──
                self::pkg('سوبر مكس — أسبوعي', 'mix-w', 1740, 'باقات مكس', ['days' => '7']),
                self::pkg('سوبر مكس — شهري', 'mix-m', 3740, 'باقات مكس', ['days' => '30']),
                // ── اتصال ──
                self::pkg('اتصال — أسبوعية', 'call-w', 1300, 'باقات الاتصال', ['days' => '7']),
                self::pkg('اتصال — شهرية', 'call-m', 3000, 'باقات الاتصال', ['days' => '30']),
                self::pkg('اتصال — ماكس', 'call-max', 4200, 'باقات الاتصال', ['days' => '30']),
                // ── رسائل ──
                self::pkg('رسائل — يومية', 'sms-d', 200, 'باقات الرسائل', ['days' => '1']),
                self::pkg('رسائل — أسبوعية', 'sms-w', 500, 'باقات الرسائل', ['days' => '7']),
                self::pkg('رسائل — شهرية', 'sms-m', 1100, 'باقات الرسائل', ['days' => '30']),
                // ── سمارت فورجي / فورجي ماكس ──
                self::pkg('سمارت فورجي — 1.4 جيجا', 's4g-1', 1500, 'باقات سمارت فورجي', ['data' => '1.4GB']),
                self::pkg('سمارت فورجي — 5 جيجا', 's4g-5', 4300, 'باقات سمارت فورجي', ['data' => '5GB']),
                self::pkg('فورجي ماكس — 4.5 جيجا', 'm4g-45', 3900, 'باقات فورجي ماكس', ['data' => '4.5GB']),
                self::pkg('فورجي ماكس — 10 جيجا', 'm4g-10', 6000, 'باقات فورجي ماكس', ['data' => '10GB']),
                // ── باقات اجتماعية ──
                self::pkg('اجتماعية — واتساب', 'soc-wa', 1800, 'الباقات الاجتماعية', ['days' => '30']),
                self::pkg('اجتماعية — تيليجرام', 'soc-tg', 2100, 'الباقات الاجتماعية', ['days' => '30']),
                self::pkg('اجتماعية — سناب شات', 'soc-sc', 2300, 'الباقات الاجتماعية', ['days' => '30']),
                self::pkg('اجتماعية — فيسبوك', 'soc-fb', 2500, 'الباقات الاجتماعية', ['days' => '30']),
                self::pkg('اجتماعية — انستقرام', 'soc-ig', 3500, 'الباقات الاجتماعية', ['days' => '30']),
                // ── سمارت نت ──
                self::pkg('سمارت نت — أسبوعي', 'snet-w', 1200, 'باقات سمارت نت', ['days' => '7']),
                self::pkg('سمارت نت — شهري', 'snet-m', 3000, 'باقات سمارت نت', ['days' => '30']),
                self::pkg('سمارت نت — سوبر', 'snet-s', 3300, 'باقات سمارت نت', ['days' => '30']),
                self::pkg('سمارت نت — ماكس', 'snet-x', 5300, 'باقات سمارت نت', ['days' => '30']),
                // ── تجوال ──
                self::pkg('تجوال — شبكات عربية', 'roam-ar', 2880, 'باقات التجوال'),
                self::pkg('تجوال — بلا حدود أسبوع', 'roam-w', 5760, 'باقات التجوال', ['days' => '7']),
                // ── فوترة ──
                self::pkg('تواصل نت برو', 'ft-netpro', 5999, 'باقات الفوترة', ['paytype' => 'postpaid', 'days' => '30']),
                self::pkg('سوبر تواصل — أسبوعي', 'ft-st-w', 1600, 'باقات الفوترة', ['paytype' => 'postpaid', 'days' => '7']),
                self::pkg('سوبر تواصل — شهري', 'ft-st-m', 2400, 'باقات الفوترة', ['paytype' => 'postpaid', 'days' => '30']),
                self::pkg('سوبر تواصل — ماكس', 'ft-st-x', 6500, 'باقات الفوترة', ['paytype' => 'postpaid', 'days' => '30']),
                self::pkg('أمان — أسبوعي', 'ft-am-w', 1450, 'باقات الفوترة', ['paytype' => 'postpaid', 'days' => '7']),
                self::pkg('أمان — شهري', 'ft-am-m', 2800, 'باقات الفوترة', ['paytype' => 'postpaid', 'days' => '30']),
            ]],

            ['code' => 'saba', 'name_ar' => 'سبأفون', 'category' => 'mobile',
             'provider_endpoint' => 'sabaphone', 'sort_order' => 3,
             'meta' => [
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']],
                'tabs' => ['rasid', 'fory', 'packages'],
                'unit_price' => 12.05, 'unit_label' => 'وحدة',
                'color' => '#B03A2E',
             ],
             'packages' => [
                // ── فوري (سعر شامل الضريبة) ──
                ...self::fories('both', [[40, 482], [45, 542], [60, 723], [85, 1024],
                    [100, 1205], [125, 1506], [150, 1808], [209, 2518],
                    [300, 3615], [505, 6085], [1270, 15304]]),
                // ── جي اس ام ──
                self::pkg('جي اس ام — أسبوعية', 'gsm-w', 1004, 'باقات جي اس ام', ['days' => '7']),
                self::pkg('جي اس ام — شهرية', 'gsm-m', 1936, 'باقات جي اس ام', ['days' => '30']),
                // ── و4-فورجي ──
                self::pkg('انتر فورجي — 15 جيجا', 'w4g-15', 7260, 'باقات و4-فورجي', ['data' => '15GB']),
                self::pkg('يابلكش فورجي — شهري', 'w4g-yf', 2390, 'باقات و4-فورجي', ['days' => '30']),
                self::pkg('هايرد — 3 جيجا', 'w4g-h3', 1400, 'باقات و4-فورجي', ['data' => '3GB']),
                self::pkg('هايرد — 8 جيجا', 'w4g-h8', 3350, 'باقات و4-فورجي', ['data' => '8GB']),
                // ── يابلكش + واحد ──
                self::pkg('يابلكش — يومية', 'yb-d', 575, 'باقات يابلكش + واحد', ['days' => '1']),
                self::pkg('يابلكش — أسبوعية', 'yb-w', 484, 'باقات يابلكش + واحد', ['days' => '7']),
                self::pkg('يابلكش — 10 أيام', 'yb-10', 1330, 'باقات يابلكش + واحد', ['days' => '10']),
                self::pkg('يابلكش — شهري', 'yb-m', 1210, 'باقات يابلكش + واحد', ['days' => '30']),
                self::pkg('سوبر بلاس', 'yb-sp', 3025, 'باقات يابلكش + واحد'),
                self::pkg('واحد — 1.5 جيجا / 48 ساعة', 'wahed-15', 875, 'باقات يابلكش + واحد', ['data' => '1.5GB', 'days' => '2']),
                // ── تواصل / سوبرنت / رسائل / اجتماعي ──
                self::pkg('تواصل انترناشيونال', 'tw-int', 1000, 'باقات تواصل'),
                self::pkg('سوبرنت — شهري', 'snet-m', 1500, 'باقات سوبرنت', ['days' => '30']),
                self::pkg('رسائل — شهري', 'sms-m', 300, 'باقات الرسائل', ['days' => '30']),
                self::pkg('اجتماعي — شهري', 'soc-m', 900, 'باقات اجتماعي', ['days' => '30']),
            ]],

            ['code' => 'sbay', 'name_ar' => 'سبأي (SabaY)', 'category' => 'mobile',
             'provider_endpoint' => 'sbay', 'sort_order' => 4,
             'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']]]],

            ['code' => 'yem4g', 'name_ar' => 'يمن 4G', 'category' => 'mobile',
             'provider_endpoint' => 'yem4g', 'sort_order' => 5,
             'meta' => [
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم المشترك'],
                             ['key' => 'type', 'type' => 'select', 'label' => 'نوع الخط',
                              'options' => [['v' => '1', 'l' => 'مسبق الدفع'], ['v' => '2', 'l' => 'فوترة']]]],
                'query' => true, 'color' => '#1B6AC9',
            ]],

            ['code' => 'adenet', 'name_ar' => 'عدن نت', 'category' => 'mobile',
             'provider_endpoint' => 'adenet', 'sort_order' => 6,
             'meta' => [
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم المشترك']],
                'tabs' => ['rasid', 'packages'], 'query' => true, 'color' => '#0E8A8A',
             ],
             'packages' => [
                self::pkg('باقة 20 جيجا', 'gb20', 3150, 'باقات عدن نت', ['data' => '20GB']),
                self::pkg('باقة 40 جيجا', 'gb40', 6300, 'باقات عدن نت', ['data' => '40GB']),
                self::pkg('باقة 60 جيجا', 'gb60', 9450, 'باقات عدن نت', ['data' => '60GB']),
                self::pkg('باقة 80 جيجا', 'gb80', 12600, 'باقات عدن نت', ['data' => '80GB']),
                self::pkg('120 جيجا تجاري', 'gb120b', 31500, 'باقات عدن نت', ['data' => '120GB', 'note' => 'باقة تجارية']),
            ]],

            // ── Way (واي) — provider endpoint «why» ────────────────
            ['code' => 'way', 'name_ar' => 'واي', 'category' => 'mobile',
             'provider_endpoint' => 'way', 'sort_order' => 7,
             'meta' => [
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']],
                'tabs' => ['rasid', 'fory', 'packages'], 'color' => '#4A148C',
             ],
             'packages' => [
                // ── فوري ──
                ...self::fories('both', [[180, 218], [500, 605], [900, 1089], [2000, 2420]]),
                // ── الو ──
                self::pkg('الو — 250 جيجا', 'alo-250', 303, 'باقات الو', ['data' => '250GB']),
                self::pkg('الو — 500 جيجا', 'alo-500', 605, 'باقات الو', ['data' => '500GB']),
                self::pkg('الو — 900 جيجا', 'alo-900', 1089, 'باقات الو', ['data' => '900GB']),
                self::pkg('الو — 2000 جيجا', 'alo-2000', 2420, 'باقات الو', ['data' => '2000GB']),
                // ── كرم ──
                self::pkg('كرم — 7 أيام', 'karam-7', 303, 'باقات كرم', ['days' => '7']),
                self::pkg('كرم — 30 يوم', 'karam-30', 605, 'باقات كرم', ['days' => '30']),
                self::pkg('كرم — 45 يوم', 'karam-45', 1089, 'باقات كرم', ['days' => '45']),
                self::pkg('كرم — 60 يوم', 'karam-60', 2420, 'باقات كرم', ['days' => '60']),
                // ── مكالمات ──
                self::pkg('مكالمات شبكة الواي — 500', 'calls-500', 605, 'باقات المكالمات'),
                self::pkg('رصيد كبير — 6000', 'bal-6000', 7260, 'باقات المكالمات'),
            ]],

            // ── Landline / ADSL / Fiber ────────────────────────────
            ['code' => 'post', 'name_ar' => 'هاتف ثابت / ADSL', 'category' => 'landline',
             'provider_endpoint' => 'post', 'sort_order' => 10,
             'meta' => [
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 8, 'label' => 'رقم الهاتف الثابت'],
                             ['key' => 'type', 'type' => 'select', 'label' => 'نوع الخدمة',
                              'options' => [['v' => 'line', 'l' => 'هاتف أرضي'], ['v' => 'adsl', 'l' => 'ADSL / يمن نت'], ['v' => 'ftth', 'l' => 'فايبر FTTH']]]],
                'tabs' => ['rasid', 'packages'], 'query' => true, 'color' => '#2E4057',
             ],
             'packages' => [
                // فئات الهاتف الثابت (سداد مبلغ)
                self::pkg('سداد — 250', 'p250', 250, 'سداد مبالغ — هاتف ثابت'),
                self::pkg('سداد — 500', 'p500', 500, 'سداد مبالغ — هاتف ثابت'),
                self::pkg('سداد — 1000', 'p1000', 1000, 'سداد مبالغ — هاتف ثابت'),
                // باقات يمن نت ADSL (كما في تطبيق المزود)
                self::pkg('سوبر نت 1M — 10 جيجا', 'sn1m', 1575, 'باقات الانترنت الأرضي ADSL', ['params' => ['type' => 'adsl'], 'data' => '10GB']),
                self::pkg('جيجا 24 — 2M', 'g24', 2520, 'باقات الانترنت الأرضي ADSL', ['params' => ['type' => 'adsl'], 'data' => '24GB']),
                self::pkg('س ش 28 جيجا — 2M', 'sh28', 2900, 'باقات الانترنت الأرضي ADSL', ['params' => ['type' => 'adsl'], 'data' => '28GB']),
                self::pkg('الحجم 1M — 24 جيجا', 'h1m24', 3150, 'باقات الانترنت الأرضي ADSL', ['params' => ['type' => 'adsl'], 'data' => '24GB']),
                self::pkg('جيجا 50 — 2M', 'g50', 4725, 'باقات الانترنت الأرضي ADSL', ['params' => ['type' => 'adsl'], 'data' => '50GB']),
                self::pkg('س ش 54 جيجا — 2M', 'sh54', 5200, 'باقات الانترنت الأرضي ADSL', ['params' => ['type' => 'adsl'], 'data' => '54GB']),
                // ── فايبر FTTH — القائمة الرسمية الجديدة للاتصالات اليمنية ──
                // الاتصال الصوتي مجاناً داخل الشبكة الثابتة لكل الباقات
                self::pkg('فايبر 36 جيجا — 10M', 'ftth10-36', 4000, 'فايبر 10M', ['params' => ['type' => 'ftth'], 'data' => '36GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 84 جيجا — 10M', 'ftth10-84', 8000, 'فايبر 10M', ['params' => ['type' => 'ftth'], 'data' => '84GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 177 جيجا — 10M', 'ftth10-177', 16000, 'فايبر 10M', ['params' => ['type' => 'ftth'], 'data' => '177GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 60 جيجا — 25M', 'ftth25-60', 6600, 'فايبر 25M', ['params' => ['type' => 'ftth'], 'data' => '60GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 140 جيجا — 25M', 'ftth25-140', 13300, 'فايبر 25M', ['params' => ['type' => 'ftth'], 'data' => '140GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 300 جيجا — 25M', 'ftth25-300', 27000, 'فايبر 25M', ['params' => ['type' => 'ftth'], 'data' => '300GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 140 جيجا — 50M', 'ftth50-140', 15400, 'فايبر 50M', ['params' => ['type' => 'ftth'], 'data' => '140GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 320 جيجا — 50M', 'ftth50-320', 30400, 'فايبر 50M', ['params' => ['type' => 'ftth'], 'data' => '320GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 670 جيجا — 50M', 'ftth50-670', 60300, 'فايبر 50M', ['params' => ['type' => 'ftth'], 'data' => '670GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 340 جيجا — 100M', 'ftth100-340', 37400, 'فايبر 100M', ['params' => ['type' => 'ftth'], 'data' => '340GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 780 جيجا — 100M', 'ftth100-780', 74000, 'فايبر 100M', ['params' => ['type' => 'ftth'], 'data' => '780GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 1500 جيجا — 100M', 'ftth100-1500', 140000, 'فايبر 100M', ['params' => ['type' => 'ftth'], 'data' => '1500GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 3000 جيجا — 100M', 'ftth100-3000', 270000, 'فايبر 100M', ['params' => ['type' => 'ftth'], 'data' => '3000GB', 'minutes' => 'مجاناً']),
                self::pkg('فايبر 4000 جيجا — 200M', 'ftth200-4000', 400000, 'فايبر 200M', ['params' => ['type' => 'ftth'], 'data' => '4000GB', 'minutes' => 'مجاناً']),
                self::pkg('66 جيجا — 4M', 'g66', 6930, 'باقات الانترنت الأرضي ADSL', ['params' => ['type' => 'adsl'], 'data' => '66GB']),
            ]],

            // ── Utilities ──────────────────────────────────────────
            ['code' => 'elect', 'name_ar' => 'فاتورة الكهرباء', 'category' => 'utility',
             'provider_endpoint' => 'electwater', 'sort_order' => 20,
             'meta' => ['act' => 'elect',
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 0, 'label' => 'رقم المشترك'],
                             ['key' => 'placeid', 'type' => 'text', 'label' => 'المنطقة']],
                'places' => [], 'query' => true]],
            ['code' => 'water', 'name_ar' => 'فاتورة الماء', 'category' => 'utility',
             'provider_endpoint' => 'electwater', 'sort_order' => 21,
             'meta' => ['act' => 'water',
                'fields' => [['key' => 'num', 'type' => 'number', 'len' => 0, 'label' => 'رقم المشترك'],
                             ['key' => 'placeid', 'type' => 'text', 'label' => 'المنطقة']],
                'places' => [], 'query' => true]],

            // ── Games & gift cards ─────────────────────────────────
            ['code' => 'games', 'name_ar' => 'ألعاب وبطاقات', 'category' => 'game',
             'provider_endpoint' => 'gameswcards', 'sort_order' => 30,
             'meta' => ['fields' => [
                ['key' => 'type', 'type' => 'select', 'label' => 'نوع البطاقة', 'options' => [
                    ['v' => 'pubg', 'l' => 'PUBG Mobile'], ['v' => 'freefire', 'l' => 'Free Fire'],
                    ['v' => 'legends', 'l' => 'Mobile Legends'], ['v' => 'clashofclanz', 'l' => 'Clash of Clans'],
                    ['v' => 'clashroial', 'l' => 'Clash Royale'], ['v' => 'genshmbacket', 'l' => 'Genshin Impact'],
                    ['v' => 'newstatepobg', 'l' => 'PUBG New State'], ['v' => 'calloffdyoty', 'l' => 'Call of Duty'],
                    ['v' => 'crossfire', 'l' => 'CrossFire'], ['v' => 'googleplayusa', 'l' => 'Google Play US'],
                    ['v' => 'googleplaykorea', 'l' => 'Google Play Korea'], ['v' => 'appstore', 'l' => 'App Store / iTunes'],
                    ['v' => 'beinconnect', 'l' => 'beIN Connect'], ['v' => 'razergold', 'l' => 'Razer Gold'],
                    ['v' => 'plastationusa', 'l' => 'PlayStation US'], ['v' => 'plastationsar', 'l' => 'PlayStation KSA'],
                    ['v' => 'visacard', 'l' => 'Visa Card'], ['v' => 'mastercard', 'l' => 'Mastercard'],
                    ['v' => 'likee', 'l' => 'Likee'], ['v' => 'bigolive', 'l' => 'Bigo Live'],
                    ['v' => 'praolstars', 'l' => 'Brawl Stars'], ['v' => 'hidadijwaher', 'l' => 'هدية جواهر'],
                    ['v' => 'ddihadi', 'l' => 'هدية'], ['v' => 'pompitch', 'l' => 'Pompitch'],
                ]],
                ['key' => 'uniqcode', 'type' => 'text', 'label' => 'كود الفئة (uniqcode)'],
                ['key' => 'playerid', 'type' => 'text', 'label' => 'معرّف اللاعب'],
                ['key' => 'playername', 'type' => 'text', 'label' => 'اسم اللاعب'],
                ['key' => 'zoneid', 'type' => 'text', 'label' => 'Zone ID (إن وجد)'],
                ['key' => 'email', 'type' => 'email', 'label' => 'البريد الإلكتروني'],
            ]]],

            // ── Wholesale ──────────────────────────────────────────
            ['code' => 'sabagomla', 'name_ar' => 'جملة سبأفون', 'category' => 'wholesale',
             'provider_endpoint' => 'sabagomla', 'sort_order' => 40,
             'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']]]],
            ['code' => 'mtngomla', 'name_ar' => 'جملة MTN', 'category' => 'wholesale',
             'provider_endpoint' => 'mtngomla', 'sort_order' => 41,
             'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']]]],
            ['code' => 'mobilegomla', 'name_ar' => 'جملة يمن موبايل', 'category' => 'wholesale',
             'provider_endpoint' => 'mobilegomla', 'sort_order' => 42,
             'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']]]],
        ];

        foreach ($services as $s) {
            TopupServiceSetting::updateOrCreate(
                ['code' => $s['code']],
                $s + ['account' => 'south', 'fee_type' => 'none', 'fee_value' => 0]
            );
        }
    }

    /**
     * Build a فوري denomination row set: name = «فئة X», price = الفئة ×
     * معامل الشبكة — billed through the service endpoint (kind = fory).
     */
    private static function fories(string $network, array $pairs): array
    {
        $netLabel = $network === 'south' ? ' (جنوب)' : ($network === 'north' ? ' (شمال)' : '');
        return array_map(
            fn (array $p) => self::pkg(
                'فئة ' . $p[0] . $netLabel,
                'fory-' . $network . '-' . $p[0],
                $p[1],
                'فوري — فئات',
                ['network' => $network]
            ),
            $pairs
        );
    }

    /**
     * Duplicate a catalog for both gateways — the south-priced row plus a
     * north-priced twin (south ÷ 3.05, rounded to a clean figure) so the
     * app shows each gateway's own price list like TaizTel's شمال/جنوب tabs.
     * Row format: [name, code, southPrice, group, extra?]
     */
    private static function dual(array $rows, float $rate = 3.05): array
    {
        $out = [];
        foreach ($rows as $r) {
            [$name, $code, $price, $group] = $r;
            $extra = $r[4] ?? [];
            $out[] = self::pkg($name, $code . '-s', $price, $group, $extra + ['network' => 'south']);
            $north = max(5, round($price / $rate / 5) * 5);
            $out[] = self::pkg($name, $code . '-n', $north, $group, $extra + ['network' => 'north']);
        }
        return $out;
    }
}
