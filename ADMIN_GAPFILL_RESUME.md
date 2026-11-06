# نقطة استئناف — سد ثغرات لوحة المشرف (اشتراكات MikroTik + المحاسبة)

آخر تحديث: نهاية جلسة العمل (قبل التوقف للمساء)

---

## بيانات الوصول (مؤكدة لايف)

| العنصر | القيمة |
|---|---|
| لوحة المشرف | `https://staging.saiberwifi.net/admin` |
| البريد | `admin@saiberwifi.net` |
| كلمة المرور | `Admin@2025!` |
| ملاحظة | حساب ثانٍ `admin-demo@saiberwifi.local` موجود لكن كلمة مروره غير مؤكدة |

الاعتمادية مؤكدة عبر `Hash::check` على السيرفر + دخول فعلي ناجح بالمتصفح.

## ما اكتمل ✅

### 1. البنية (منشورة على staging — migrate DONE)
- `acc_plans` + `acc_payment_requests` + `acc_subscriptions` أُنشئت (كانت ناقصة كلياً على staging — سبب فشل الترحيل الأول)
- `acc.*` settings زُرعت (trial_days=30, enforce=0, free_features, pricing_note, trial_is_paid)
- `granted_features`/`revoked_features` JSON أُضيفت لجدولي الاشتراكات — الترحيل الآن **idempotent** (`hasTable`/`hasColumn` guards)

### 2. المنطق (منشور)
- `entitlements()` في كلا الكنترولرين: `base + granted − revoked` مفلترة بمفاتيح الميزات المعروفة
- إنشاء اشتراك MikroTik يدوياً من اللوحة («منح اشتراك»)
- إشعار المالك عند موافقة/رفض طلب الدفع (`notifyOwner`)

### 3. موارد Filament الجديدة (منشورة وتعمل)
- مجموعة «المحاسبة»: خطط المحاسبة، اشتراكات المحاسبة، مدفوعات المحاسبة
- كلها تظهر في القائمة الجانبية وتفتح بلا أخطاء

### 4. أصول Filament — إصلاح بنيوي كبير
- مجلدات `js`/`fonts`/`css/filament` في docroot (`public_html/staging`) كانت **تالفة inode** (`d?????????` — كل أصول اللوحة 404 → اللوحة كانت معطلة كلياً على staging)
- الحل: `mv` للمجلدات التالفة إلى `*_broken` + إنشاء جديدة + نسخ من `staging-app/public`
- **اللوحة كانت مكسورة قبل هذا الإصلاح — الآن تعمل بالكامل**

### 5. إصلاح منهجي لـ closures غير المسماة (منشور)
Filament يحلّ الوسائط بالاسم/النوع فقط — `fn($r)`/`fn($s)` غير المكتوبة تُحقن بـ `null`:
- أخطاء حرجة أُصلحت: `visible(fn($r))` في إجراءات المدفوعات (كان 500)، `getStateUsing(fn($r))` في الرواتر (كان 500)
- أخطاء صامتة أُصلحت: شارات كانت تعرض فارغة (`fn($s)`→`fn($state)`) في 10+ موارد، عدد ميزات الخطط (`fn($r)`→`fn($record)`)، زر موافقة صاحب الشبكة كان يظهر دائماً (`NetworkOwnerResource:107`)
- ملفات معدّلة: موارد المدفوعات/الاشتراكات/الخطط/الرواتر + NetworkOwner, Network, Transaction, WalletLog, PayoutRequest, Region, Report, Advance, AdvanceCategorySetting, CardCategory

### 6. بيانات فاسدة أُصلحت
- `mikrotik_plans.features` كان **JSON مُرمّز مرتين** (تخزين يدوي سابق) — أُعيد ترميز الصفوف الثلاثة على staging؛ cast يعيد مصفوفة صحيحة الآن

### 7. تحقق المستخدم (Playwright على Edge/Chromium النظام)
- تسجيل الدخول ✅، لوحة التحكم ✅، **20/20 صفحة مورد بدون 500** ✅
- إنشاء خطة محاسبة من النموذج الفعلي ✅ (سجل: `خطة اختبار المحاسبة` / 15000 / 30 يوم / 28 ميزة)
- التحقق من الحقول المطلوبة يعمل ✅
- قوائم granted/revoked في نموذج الاشتراك تعرض كل الـ 28 ميزة ✅

## الاستئناف — اكتمل كلياً ✅ (2026-11-06)

كل بنود الاختبار كمستخدم تمت بنجاح:

- **منح اشتراك محاسبة** عبر الـ select البحثي (`.fi-dropdown-panel` + حقل «ابدأ بالكتابة للبحث»، والحالة `<select>` أصلي) — اشتراك `صاحب شبكة تجريبي`/خطة اختبار أُنشئ ✅
- **تعبئة تواريخ تلقائية** أُضيفت (`mutateFormDataBeforeCreate`): `starts_at=now` و`ends_at=+duration` عند اختيار خطة وترك التواريخ فارغة — كلا صفحتي الإنشاء ✅
- **موافقة MikroTik (RC-12345)**: اشتراك نشط #8 (30 يوماً) + إنهاء 3 اشتراكات قديمة + إشعار «تم تفعيل اشتراك MikroTik» ✅
- **رفض MikroTik (REJ-TEST-01)**: سبب الرفض محفوظ + إشعار «طلب دفع مرفوض» بالسبب ✅
- **موافقة محاسبة (ACC-TEST-01)**: اشتراك #2 نشط + #1 انتهى تلقائياً + إشعار «تم تفعيل اشتراك المحاسبة» ✅
- **Entitlements بتوكن حقيقي**: revoke على نشط أخفى المفتاح (17/28→17، 28→27) · grant على منتهٍ فتح مفتاحاً فوق المجانية (3+1) · الـ revoke يغلب الـ grant — سلوك مصمّم ✅
- **تعديل الخطة** عبر الواجهة: duration 30→45 محفوظة ✅
- الشارات تُترجم صحيحاً بعد إصلاح `$state`؛ رابط الكروت الفعلي `/admin/card-categories` (الـ 404 كان تخمين slug خاطئ — ليس عطلاً)
- **APK**: `network_owner_app\build\app\outputs\flutter-apk\app-debug.apk` (208MB)

## أدوات الاختبار الجاهزة (Temp)
- `admin_e2e.py`, `nav_test2.py`, `full_sweep.py`, `flow_plan3.py`, `flow_sub3.py` — Playwright قناة `msedge` headless
- `deploy_fix3.py` — رفع ملفات + `php -l` + `optimize:clear`
- لقطات: `C:\Users\HP\AppData\Local\Temp\shots\`

## ملاحظات حرجة
- **لا تلمس الإنتاج** — كل العمل على staging فقط (`staging-app` + docroot `public_html/staging`)
- مجلدات `js_broken`/`fonts_broken`/`css/filament_broken` باقية في docroot — inodes تالفة، تُترك (غير قابلة للحذف عبر المستخدم الحالي)
- بوابات الميزات تعمل بـ `FEATURE_KEYS` كلها عند اشتراك فعّال؛ `plan.features` كتالوج عرض فقط
- تعديلات المستخدم اليدوية على ملفات الموارد (نفس إصلاحات `$state`) متوافقة — لا تعارض
- المستخدم يطلب دائماً: اختبار لايف كمستخدم (ليس برمجياً فقط)، CLEAN CODE، صفر كسر لأي مهام أخرى
