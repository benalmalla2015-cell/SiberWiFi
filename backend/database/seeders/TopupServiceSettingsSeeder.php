<?php

namespace Database\Seeders;

use App\Models\TopupServiceSetting;
use Illuminate\Database\Seeder;

class TopupServiceSettingsSeeder extends Seeder
{
    public function run(): void
    {
        // meta.fields drives the dynamic payment form in the app:
        //   number      -> digits-only input (len = expected length)
        //   amount      -> face-value amount input
        //   select      -> options list
        //   text/email  -> free input
        // meta.offers  -> provider endpoint used to list number offers (or null)
        // meta.account -> which provider account to bill from
        $services = [
            // ── Mobile top-up ──────────────────────────────────────
            ['code' => 'yem',    'name_ar' => 'يمن موبايل',        'category' => 'mobile', 'provider_endpoint' => 'yem',      'sort_order' => 1, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']], 'offers' => 'yemoffer', 'query' => true]],
            ['code' => 'mtn',    'name_ar' => 'MTN / YOU',          'category' => 'mobile', 'provider_endpoint' => 'mtn',      'sort_order' => 2, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف'], ['key' => 'type', 'type' => 'select', 'label' => 'نوع الخط', 'options' => [['v' => 'prepaid', 'l' => 'مسبق الدفع'], ['v' => 'postpaid', 'l' => 'آجل الدفع']]], ['key' => 'israsid', 'type' => 'select', 'label' => 'نوع الشحن', 'options' => [['v' => '0', 'l' => 'شحن عادي'], ['v' => '1', 'l' => 'شحن رصيد']]]], 'amount_options' => [['v' => '410', 'l' => '410 ← 513 وحدة'], ['v' => '830', 'l' => '830 ← 984 وحدة'], ['v' => '1250', 'l' => '1250 ← 1481 وحدة'], ['v' => '2500', 'l' => '2500 ← 2963 وحدة'], ['v' => '5000', 'l' => '5000 ← 5925 وحدة'], ['v' => '7500', 'l' => '7500 ← 8888 وحدة'], ['v' => '1000', 'l' => '1000 ← 1250 وحدة']]],
            ['code' => 'saba',   'name_ar' => 'سبأفون',             'category' => 'mobile', 'provider_endpoint' => 'sabaphone','sort_order' => 3, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']], 'amount_options' => [['v' => '40', 'l' => '40 ← 482 وحدة'], ['v' => '45', 'l' => '45 ← 542 وحدة'], ['v' => '60', 'l' => '60 ← 723 وحدة'], ['v' => '85', 'l' => '85 ← 1024 وحدة'], ['v' => '100', 'l' => '100 ← 1205 وحدة'], ['v' => '125', 'l' => '125 ← 1506 وحدة'], ['v' => '150', 'l' => '150 ← 1808 وحدة'], ['v' => '209', 'l' => '209 ← 2518 وحدة'], ['v' => '300', 'l' => '300 ← 3615 وحدة'], ['v' => '505', 'l' => '505 ← 6085 وحدة'], ['v' => '1270', 'l' => '1270 ← 15304 وحدة']]]],
            ['code' => 'sbay',   'name_ar' => 'سبأي (SabaY)',       'category' => 'mobile', 'provider_endpoint' => 'sbay',     'sort_order' => 4, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']]]],
            ['code' => 'yem4g',  'name_ar' => 'يمن 4G',             'category' => 'mobile', 'provider_endpoint' => 'yem4g',    'sort_order' => 5, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم المشترك'], ['key' => 'type', 'type' => 'select', 'label' => 'نوع الخط', 'options' => [['v' => '1', 'l' => 'مسبق الدفع'], ['v' => '2', 'l' => 'فوترة']]]], 'query' => true]],
            ['code' => 'adenet', 'name_ar' => 'عدن نت',             'category' => 'mobile', 'provider_endpoint' => 'adenet',   'sort_order' => 6, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم المشترك']], 'query' => true]],

            // ── Landline / ADSL ────────────────────────────────────
            ['code' => 'post',   'name_ar' => 'هاتف ثابت / ADSL',   'category' => 'landline', 'provider_endpoint' => 'post',   'sort_order' => 10, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 8, 'label' => 'رقم الهاتف الثابت'], ['key' => 'type', 'type' => 'select', 'label' => 'نوع الخدمة', 'options' => [['v' => 'line', 'l' => 'هاتف أرضي'], ['v' => 'adsl', 'l' => 'ADSL']]]], 'query' => true]],

            // ── Utilities ──────────────────────────────────────────
            ['code' => 'elect',  'name_ar' => 'فاتورة الكهرباء',    'category' => 'utility', 'provider_endpoint' => 'electwater', 'sort_order' => 20, 'meta' => ['act' => 'elect', 'fields' => [['key' => 'num', 'type' => 'number', 'len' => 0, 'label' => 'رقم المشترك'], ['key' => 'placeid', 'type' => 'text', 'label' => 'المنطقة']], 'places' => [], 'query' => true]],
            ['code' => 'water',  'name_ar' => 'فاتورة الماء',       'category' => 'utility', 'provider_endpoint' => 'electwater', 'sort_order' => 21, 'meta' => ['act' => 'water', 'fields' => [['key' => 'num', 'type' => 'number', 'len' => 0, 'label' => 'رقم المشترك'], ['key' => 'placeid', 'type' => 'text', 'label' => 'المنطقة']], 'places' => [], 'query' => true]],

            // ── Games & gift cards ─────────────────────────────────
            ['code' => 'games',  'name_ar' => 'ألعاب وبطاقات',      'category' => 'game',    'provider_endpoint' => 'gameswcards', 'sort_order' => 30, 'meta' => ['fields' => [
                ['key' => 'type',       'type' => 'select', 'label' => 'نوع البطاقة', 'options' => [
                    ['v' => 'pubg', 'l' => 'PUBG Mobile'], ['v' => 'freefire', 'l' => 'Free Fire'], ['v' => 'legends', 'l' => 'Mobile Legends'],
                    ['v' => 'clashofclanz', 'l' => 'Clash of Clans'], ['v' => 'clashroial', 'l' => 'Clash Royale'], ['v' => 'genshmbacket', 'l' => 'Genshin Impact'],
                    ['v' => 'newstatepobg', 'l' => 'PUBG New State'], ['v' => 'calloffdyoty', 'l' => 'Call of Duty'], ['v' => 'crossfire', 'l' => 'CrossFire'],
                    ['v' => 'googleplayusa', 'l' => 'Google Play US'], ['v' => 'googleplaykorea', 'l' => 'Google Play Korea'], ['v' => 'appstore', 'l' => 'App Store / iTunes'],
                    ['v' => 'beinconnect', 'l' => 'beIN Connect'], ['v' => 'razergold', 'l' => 'Razer Gold'], ['v' => 'plastationusa', 'l' => 'PlayStation US'],
                    ['v' => 'plastationsar', 'l' => 'PlayStation KSA'], ['v' => 'visacard', 'l' => 'Visa Card'], ['v' => 'mastercard', 'l' => 'Mastercard'],
                    ['v' => 'likee', 'l' => 'Likee'], ['v' => 'bigolive', 'l' => 'Bigo Live'], ['v' => 'praolstars', 'l' => 'Brawl Stars'],
                    ['v' => 'hidadijwaher', 'l' => 'هدية جواهر'], ['v' => 'ddihadi', 'l' => 'هدية'], ['v' => 'pompitch', 'l' => 'Pompitch'],
                ]],
                ['key' => 'uniqcode',   'type' => 'text',  'label' => 'كود الفئة (uniqcode)'],
                ['key' => 'playerid',   'type' => 'text',  'label' => 'معرّف اللاعب'],
                ['key' => 'playername', 'type' => 'text',  'label' => 'اسم اللاعب'],
                ['key' => 'zoneid',     'type' => 'text',  'label' => 'Zone ID (إن وجد)'],
                ['key' => 'email',      'type' => 'email', 'label' => 'البريد الإلكتروني'],
            ]]],

            // ── Wholesale ──────────────────────────────────────────
            ['code' => 'sabagomla',   'name_ar' => 'جملة سبأفون',      'category' => 'wholesale', 'provider_endpoint' => 'sabagomla',   'sort_order' => 40, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']]]],
            ['code' => 'mtngomla',    'name_ar' => 'جملة MTN',         'category' => 'wholesale', 'provider_endpoint' => 'mtngomla',    'sort_order' => 41, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']]]],
            ['code' => 'mobilegomla', 'name_ar' => 'جملة يمن موبايل',  'category' => 'wholesale', 'provider_endpoint' => 'mobilegomla', 'sort_order' => 42, 'meta' => ['fields' => [['key' => 'num', 'type' => 'number', 'len' => 9, 'label' => 'رقم الهاتف']]]],
        ];

        foreach ($services as $s) {
            TopupServiceSetting::updateOrCreate(
                ['code' => $s['code']],
                $s + ['account' => 'south', 'fee_type' => 'none', 'fee_value' => 0]
            );
        }
    }
}
