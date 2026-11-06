# ACC-06 — نقطة الاستئناف (2026-10-29)

الحالة: **كل العمل منجز تقريباً — توقفنا قبل إعادة بناء الـ APK الأخير مباشرة.**

## ما أُنجز

### Backend (كل الملفات `acc_*` فقط)
- 3 migrations: `060001 acc_sales`, `060002 acc_sale_items`, `060003 acc_commissions`
- Models: `AccSale`, `AccSaleItem`, `AccCommission`
- `AccDistService` (دورة البيع الذرّية: مخزون + صندوق + دين + عمولة + قيد عبر `AccPostingService` فقط) + `AccDistException`
- `AccDistController` + routes `/dist/{home,sales,sale,report,commissions}` (صلاحيات dist.*)
- خطاف عمولة الموزع في `AccPosOrderService` (عند الاعتماد)
- `tests/Feature/AccDistTest.php` — **16/16 أخضر**، وكامل حزمة acc **82/82 أخضر**

### إصلاحان حقيقيان ظهرا فقط على MySQL (sqlite لا يفرض FK)
1. `acc_collections.debt_id → acc_debts` — FK أمامي (050003 قبل 050004). الحل: إزالة القيد من `050003` + migration جديد `2026_10_27_050008_add_acc_collections_debt_fk.php` (عدّلت ملف ACC-05 — أُبلغ التنسيق).
2. `acc_journal_entries.agent_id` + `acc_audit_log.agent_id` كانا FK→`users` والكود يكتب `acc_agents.id`. الحل: أعمدة عادية في `010002`/`010005` + migration تصحيحي `2026_10_27_020004_fix_acc_agent_fks.php` (يسقط FK الخاطئ إن وُجد ويضيف الصحيح — يعمل للتثبيت الجديد والمنشور).

### Flutter (`features/accounting/` فقط)
- `data/dist_api.dart` (كل النماذج + `_write` يستخرج رسالة 422 العربية)
- `providers/dist_providers.dart`
- 4 شاشات: `dist_home_screen` (بطل + إحصاءات اليوم + فئات بمتبقٍّ يومي + نقاط بذممهن + شبكة أفعال)، `dist_sale_screen` (أصناف ديناميكية + نقدي/آجل/جزئي + idempotency key ثابت للنموذج)، `dist_sales_screen`، `dist_report_screen` (تبويبا التقرير/العمولات)
- `acc_home_screen`: دور الموزع → `DistHomeScreen` خلف `FeatureGate(acc.distributor)`
- التحصيلات/المديونيات/طلبات النقاط تُعاد استخدام شاشات ACC-05/04 (نفس الصلاحيات)

### توسعة بوابة الدخول (خارج نطاق accounting — يُبلَّغ التنسيق)
الخطة §1 تنص: «الموظف يدخل نفس تطبيق المالك». التطبيق كان يرفض أي مستخدم ليس `network_owner` — أي أنه **مستحيل** دخول موزع/POS أبداً. الإصلاح الأدنى:
- `auth_repository.dart`: +`hasAccountingSession()` يستعلم `/accounting/me`
- `auth_provider.dart`: يقبل المستخدم غير-المالك **فقط إذا** حُلّت جلسة acc (تدفق المالك لم يتغير) — في `login()` و`_checkAuth()`

## النشر على staging
- **اكتشاف**: لم يُنشر أي backend محاسبة أبداً (لا جداول acc_) — سجلات ACC السابقة كانت ADB فقط
- `tools/deploy_acc06.py` رفع كل السطح (موديلات/خدمات/كنترولرات/ميدلوير/مزوّد + bootstrap/providers.php + كل migrations باستثناء 2026_10_29_* لمسارات قيد الطيران) + `php artisan migrate` — **33 migration نجحت كلها** (شملت 070001/070002 لـ ACC-07 — إضافية غير مؤذية)
- migration ملفات `2026_10_29_*acc*` حُذفت عن بعد لأنها مسارات وكلاء آخرين
- `tools/acc06_seed.php` (يحتاج `require vendor/autoload.php` — مُصلح): مستخدم موزع `700000011`/`123456` (user #170)، agent #2 موزع بعمولة 5%، نقطة بيع #2 «بقالة النور»، فئتان #4/#5 بمخزون، صندوق #2

## التحقق الحي عبر API (curl — كله يعمل)
- `/me` → `role: distributor`, owner 91, صلاحيات dist.*
- `/dist/home` → فئات+مخزون+نقاط+عدّادات
- بيع جزئي `SA-20261029-000001`: إجمالي 5000، مدفوع 3000، متبقٍّ 2000 (دين #7)، عمولة 250 (5%)، قيد #20
- إعادة إرسال بنفس مفتاح idempotency → نفس البيع (لا تكرار) ✔
- `/dist/debts/7/pay` مبلغ 1000 → المتبقي 1000، الحالة partial، AR انخفض لـ 1000، التحصيلات اليومية 1000
- بيع نقدي `SA-20261029-000002` مدفوع 6000 عمولة 300
- `/dist/report` + `/dist/commissions` (الفترة 2026-10: مبيعات 5000، عمولة 250، مستحقة) ✔

## أين توقفنا بالضبط
- ADB: الجهاز `7xeixgt44lvccilj` (Redmi Note 8 Pro) متصل؛ APK مُثبّت يحوي شاشات الموزع **لكن قبل إصلاح بوابة الدخول**
- أول محاولة دخول رُفضت: «هذا الحساب ليس حساب صاحب شبكة» ← أصلحناها (فوق)
- **آخر خطوة مرفوضة من المستخدم**: `flutter build apk --debug` لإعادة البناء مع إصلاح البوابة ← نستأنف من هنا

## المتبقي عند الاستئناف
1. `cd testapp/network_owner_app && flutter build apk --debug`
2. `adb -s 7xeixgt44lvccilj install -r build/app/outputs/flutter-apk/app-debug.apk`
3. مسح بيانات التطبيق ثم الدخول بـ `700000011` / `123456` → يجب أن يقبل ثم تظهر «المحاسبة» → واجهة الموزع
4. تنفيذ حي داخل الواجهة: بيع نقدي/آجل، مبيعاتي، تقريري وعمولاتي، تحصيل/سداد دين، طلبات النقاط — ولقطات `adb exec-out screencap` إلى `testapp/adb_screens/`
5. تحديث `TASKS.md` (صف ACC-06 → ✅ + عدّاد 7/33) و`PLAN.md` (سجل إنجاز ACC-06 + توثيق إصلاحَي الـFK وتوسعة البوابة)
6. رسالة `task_complete` إلى `.autoclaw/orchestrator/comms/inboxes/shared/` + `review_request` + فحص صندوق windsurf — و**الإبلاغ عن**: تعديل ملفَّي ACC-01/ACC-05 migrations، وتعديل auth_provider/repository خارج نطاق accounting، وفشل AccPosAppTest الثلاثي (ملك ACC-07: تطابق أنواع + إشارة سحب)
7. تقرير نهائي للمستخدم بالعربية

## حقائق بيئية
- PHP: `C:\php-8.5.8\php.exe` · Flutter: `C:\Users\HP\Downloads\3inab\flutter\bin\flutter` · ADB: `C:\Users\HP\AppData\Local\Android\Sdk\platform-tools\adb.exe` (الاسم الكامل لازم)
- staging: `https://staging.saiberwifi.net/api` — نشر عبر `py testapp/tools/deploy_acc06.py` (اعتمادات من staging_deploy.py)
- حسابات: موزع `700000011`/`123456` · مالك التجريبي `#91` (778257546)
- خطأ 500 من `/dist/sale` كان يُرجع `agent_id` FK — حُلّ بـ migration 020004
- `AccPosAppTest` (ACC-07) به 3 فشلات موجودة — ليست من عملي
