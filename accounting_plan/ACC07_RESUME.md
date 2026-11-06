# ACC-07 — نقطة استئناف (توقف مؤقت للمساء)

## المنجز
- Backend كامل: `acc_withdrawals` + `acc_card_exchanges` (migrations 070001/070002) + موديلان + `AccPosAppService` (home/ledger/withdrawals/exchange) + `AccPosAppController` + `AccWithdrawalsController` + مسارات `/pos/*` + `/withdrawals/*` (append فقط).
- الاختبارات: `AccPosAppTest` 16/16 (127 تأكيداً) — كامل مجموعة acc 98 اختباراً خضراء (إخفاقا `AdminUserPasswordUpdateTest` مسبقان — قيد SQLite ENUM، خارج النطاق).
- Flutter: `pos_app_api.dart` + `pos_app_providers.dart` + 4 شاشات (`pos_home` / `pos_withdrawals` / `pos_exchange` / `pos_collections`) + توجيه POS في `acc_home_screen` → `PosHomeScreen` + ترقية نموذج طلب الحزم لقائمة `category_id`. `dart analyze lib/features/accounting` نظيف.
- النشر: `testapp/tools/deploy_acc07.py` رفع 143 ملفاً لـ staging + `composer dump-autoload -o` + migrate حتى 070002 (الجلسة الموازية حسّنت تعارض `acc_collections`) + `tools/acc_seed.php` (seed ناجح: owner=102, pos_user=169, agent=1, point=1).
- تحقق API حي مباشر (curl): `/me` → role=pos ✓ · `/pos/home` → 10000 نقطة/5000 ربح + 4 حزم + سجل ✓ · POST `/pos/exchange-cards` (باقة ساعة ×2 → ‏-200 نقطة) ✓ · POST `/pos/withdrawals` (500 → حجز معلّق) ✓ · `/pos/collections-received` + `/pos/exchanges` ✓ — الرصيد الآن 9800 نقطة / 4500 ربح.

## أين توقفنا بالضبط — ADB
- APK debug مبني ومنصّب على الجهاز (`com.saiberwifi.network_owner_app.staging` على Redmi Note 8 Pro `7xeixgt44lvccilj`).
- أدوات القيادة: `live_test/adbtool.py` (launch/nodes/tap/taptxt/fill/shot/edit_fields).
- لقطات محفوظة: `live_test/acc07_01_launch.png` + `acc07_02_login_filled.png` + `acc07_03_after_login.png`.
- **العائق:** شاشة الدخول رفضت مستخدم POS ‏(700000090/123456‏) برسالة «هذا الحساب ليس حساب صاحب شبكة» — `AuthController::login` يقبل فقط `type=network_owner` أو من له `networks`/`networkOwnerProfile` (سطر ~116). مستخدم POS نوعه `client`.
- **تحذير المستخدم (مهم):** الحسابات مرتبطة بجهاز واحد + توجد حسابات استثنائية لمراجعين جوجل بلاي — يُمنع تعديل/إنشاء حسابات على نحو يمس ذلك. يجب التأكيد مع المستخدم قبل أي حل.

## خيارات الاستئناف المقترحة (تُعرض على المستخدم قبل التنفيذ)
1. استخدام حساب موجود مسبقاً من الحسابات الاستثنائية المعتمدة على هذا الجهاز وربطه كوكيل POS في `acc_agents` (تعديل محاسبي فقط — بلا لمس حسابات المنصة).
2. إنشاء حساب POS من داخل التطبيق نفسه (تسجيل صاحب شبكة ثم ربطه pos — يرتّب ربط الجهاز طبيعياً).
3. تغيير `type` لمستخدم POS الحالي (مرفوض مبدئياً — عدّل بوابة الدخول لحساب اختباري).

## المتبقي بعد ADB
- لقطات دور POS كاملة (home/حزم/سحب/استبدال/تحصيلات/طلبات) في `live_test/`.
- تحديث `TASKS.md` (صف ACC-07 ✅) + `PLAN.md` (الحالة + سجل الإنجاز) — دون المساس بتعديلات المستخدم الأخيرة (ACC-08→12 ✅).
- رسائل البروتوكول: `task_complete` لـ shared inbox + `review_request` + فحص صندوق windsurf في النهاية.
- تقرير نهائي للمستخدم.
