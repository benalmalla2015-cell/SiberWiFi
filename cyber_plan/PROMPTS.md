# مطالبات التنفيذ — سايبر نت (لكل محادثة منفصلة)

> انسخ المطالبة المناسبة في محادثة جديدة. كل مهمة ملزمة بـ: قراءة `cyber_plan/PLAN.md` (عقد العزل) + `TASKS.md` أولاً، العمل ضمن نطاق `cyber_*` فقط، clean code قابل للتوسع، صفر مساس بالنواة، وتحديث `TASKS.md` + سجل النتائج عند الإكمال.

## قالب عام لأي مهمة

```
أنت تنفّذ مهمة [CYB-XX] من مشروع «سايبر نت» داخل testapp.
إلزامي قبل الكود: اقرأ testapp/cyber_plan/PLAN.md وTASKS.md بالكامل.
النطاق المملوك: cyber_* + cyber-radius/ + routes/api_cyber.php فقط.
ممنوع: acc_*, mikrotik_*, auth, wallets, أي جدول قائم.
المطلوب: [نص المهمة من TASKS.md].
معيار القبول: [من TASKS.md].
التسليم: كود نظيف قابل للتوسع + PHP lint + flutter analyze + اختبار/لقطات ADB + تحديث TASKS.md وسجل النتائج.
```

## CYB-00 — التأسيس المعزول
سجّل `CyberServiceProvider`، أنشئ `routes/api_cyber.php` تحت `/api/cyber`، مفاتيح ميزات `cyber.*`، مجلد `cyber-radius/` بـ README المعمارية. بلا أي سلوك جديد — تأسيس فقط.

## CYB-01 — سيرفر RADIUS + CA
حزمة Docker داخل `cyber-radius/`: FreeRADIUS 3.2 + OpenSSL — توليد CA خاص بسايبر، سكربت `issue-cert.sh` (يصدر شهادة مشترك مشفّرة بالرقم) و`revoke-cert.sh`، إعداد `eap` لـ EAP-TLS فقط، `clients.conf` بمضيف واحد تجريبي، سجل auth/acct بصيغة قابلة للقراءة برمجياً.

## CYB-02 — قالب المضيف
ملف `host-templates/host.rsc.tmpl` معتم: SSID `CyberNet`، WPA2-Enterprise→RADIUS، `radius incoming` (CoA 3799)، interim-update 60s، WireGuard interface+peer للسيرفر، عزل كامل عن شبكات المضيف (bridge/list منفصل). متغيرات: `{{RADIUS_IP}}`, `{{HOST_SECRET}}`, `{{WG_*}}` — وسكربت توليد يحقنها.

## CYB-03 — التسجيل ورقم الشريحة
Migrations: `cyber_subscribers` (sim_no فريد `74#######`، اسم، محافظة، مديرية)، `cyber_documents` (بطاقة وجهين أو جواز — تخزين مسارات)، `cyber_identities` (ربط مشترك↔شهادة↔جهاز). API: `POST /cyber/register` تحقق اسم ≥4 مقاطع، رفع صور، توليد رقم فريد ذرّي، استدعاء إصدار الشهادة. ميزة: `cyber.register`.

## CYB-04 — الفوترة والقطع
`cyber_wallets`، `cyber_packages` (يوم/أسبوع/شهر + جيجات + سعر YER)، `cyber_topups` (وكيل→رقم)، `cyber_active_sessions`. خدمة `CyberBillingService`: تفعيل باقة (خصم ذرّي + idempotency)، ردّ RADIUS بـ `Mikrotik-Rate-Limit`+حد البيانات، جدولة فصل CoA، إشعار FCM عند الشحن. ميزة: `cyber.billing`.

## CYB-05+ — كما في TASKS.md بالتسلسل.
