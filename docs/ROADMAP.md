# سايبر WiFi — مستند المهام المرجعي (بيئة التطوير)

آخر تحديث: 2026-10-01
المستودع: https://github.com/benalmalla2015-cell/SiberWiFi

> هذا الملف هو المرجع الرسمي لتتبع مهام التطوير الجديدة. حدّث الحالة عند إنجاز كل مهمة.
> الرموز: ⬜ لم تبدأ | 🔶 قيد التنفيذ | ✅ منجزة | ⏸️ مؤجلة

---

## 0) البنية والبيئات

| المكوّن | الإنتاج (لا يُمس) | التطوير/التجريبي |
|---|---|---|
| Backend | `saiberwifi.net` — DB `u170359695_saiberwifi` | `staging.saiberwifi.net` → `/home/u170359695/domains/saiberwifi.net/public_html/staging` — DB `u170359695_staging` |
| تطبيق العميل | `com.saiberwifi.customerapp` | `com.saiberwifi.customerapp.staging` — «سايبر WiFi تجريبي» |
| تطبيق المالك | `com.saiberwifi.network_owner_app` | `com.saiberwifi.network_owner_app.staging` — «سايبر WiFi تجريبي» |
| السورس | `C:\Users\HP\Desktop\saiberwifi` (الأصلي) | `C:\Users\HP\Desktop\saiberwifi\testapp` (هذا المستودع) |

قواعد ذهبية:
- أي تعديل على الإنتاج ممنوع من هذا المجلد.
- كل migration جديدة يجب أن تكون additive فقط (إضافة جداول/أعمدة — لا تعديل أو حذف للموجود).
- الأسرار (.env، حسابات خدمة Firebase، كلمات مرور) لا تُرفع لـ GitHub أبدًا.

---

## 1) شحن الرصيد عبر API المزوّد — ⏸️ مؤجل بأمر المالك

- ⏸️ خدمة `YemoneyProvider` في الـ backend (نداء taiztel.yemoney.net من السيرفر فقط)
- ⏸️ جدول `recharge_requests` (transid فريد، backpass لكل عملية، حالات pending/processing/done/ban/refunded)
- ⏸️ جدول `recharge_services` (كتالوج الفئات والباقات: تكلفة + سعر بيع)
- ⏸️ خصم المحفظة: عميل ← `balance`/`available_balance` — مالك ← `available_balance` (المتاح للسحب)
- ⏸️ Webhook استقبال `?action=done|ban&backpass=&transid=` + استرداد تلقائي عند ban
- ⏸️ Polling احتياطي عبر `info?action=status` للعمليات المعلقة
- ⏸️ عرض رصيد حسابنا لدى المزوّد (`info?action=balance`) في لوحة Filament
- ⏸️ شاشات الشحن في تطبيق العميل + تطبيق المالك
- ⏸️ صافي الربح = sell_price − cost_price يُسجَّل صراحة في المعاملة

ملاحظة تنفيذية: تفاصيل الـ API موثقة في `docs/api-analysis.md` (مستخرج من API/api.pdf).

---

## 2) ربط تطبيق أصحاب الشبكات مع MikroTik

### 2.1 طبقة الاتصال — ⬜
- ⬜ إضافة `router_os_client` (MIT — تم التدقيق، انظر `docs/vendor-audit.md`)
- ⬜ خدمة `RouterConnectionService`: IP/Port/Username/Password + اختبار اتصال
- ⬜ تخزين بيانات الراوتر في `flutter_secure_storage`
- ⬜ شاشة "إعداد الراوتر" (الهوية: أزرق/أحمر/أبيض — عربي RTL)
- ⬜ (اختياري) اكتشاف تلقائي عبر `mikrotik_mndp` (MIT)

### 2.2 إدارة المستخدمين والهوتسبوت — ⬜
- ⬜ قائمة مستخدمي Hotspot `/ip/hotspot/user` (نشط/منتهي/معطل)
- ⬜ إنشاء/تعديل/حذف مستخدم + باقات `/ip/hotspot/user-profile`
- ⬜ الجلسات النشطة `/ip/hotspot/active` + قطع اتصال
- ⬜ PPPoE: `/ppp/secret` + `/ppp/active`
- ⬜ التحكم بالسرعة `/queue/simple` أو rate-limit في البروفايل

#### جديد من تحليل واجهات ميكرونت (175 لقطة — `testapp/app-micronet/`):
- ⬜ تصنيف حالة المستخدم: الكل / نشط / غير نشط / منتهي + عدادات لكل حالة + بحث بالاسم/الباقة
- ⬜ تحديد جماعي للمستخدمين (تحديد الكل / إلغاء / حذف جماعي)
- ⬜ بطاقة مستخدم تعرض: الاسم، الباقة، الحالة، الاستهلاك bytes in/out، عدد الأجهزة المتصلة
- ⬜ ربط الكرت/المستخدم بعميل محلي (إجباري في ميكرونت قبل إنشاء الكروت)
- ⬜ PPPoE كامل: تبويبات بروفايل/خادم/مستخدم، عدادات متصل/غير متصل/معطل، إضافة مستخدم (اسم+كلمة مرور+اسم عميل+سعر+هاتف+الخدمة pppoe/pptp/l2tp/ovpn+العنوان البعيد+Routes+ملاحظات+تفعيل)
- ⬜ User Manager: مستخدمين/مجموعات + صلاحيات (قراءة/كتابة/كامل/سياسات/اختبار/إعادة تشغيل)
- ⬜ تبويب "المتصلين والقيود": الجلسات النشطة + تحديث تلقائي
- ⬜ بروفايلات الهوتسبوت: بطاقة لكل بروفايل (الحد، السرعة، عدد الأجهزة) + إنشاء بروفايل v7 بالكامل (اسم، وحدة GB، رفع/تحميل، فترة زمنية، سكربت On-Login / On-Logoff) يُحفظ على الراوتر
- ⬜ باقات User Manager بالسعر: اسم، سعر، صلاحية كلية، ساعات ارتباط Uptime، عدد دخول متزامن (أجهزة)، رصيد GB/MB، تحديد سرعة — "حفظ وبرمجة الباقة"

### 2.3 الكروت — ⬜
- ⬜ توليد كرت واحد/دفعة على الراوتر
- ⬜ QR لكل كرت (`qr_flutter`)
- ⬜ طباعة حرارية ESC/POS (`esc_pos_utils_plus` — BSD)
- ⬜ تصدير PDF (`pdf`/`printing` — Apache-2.0)
- ⬜ قوالب تصميم الكرت (شعار/اسم شبكة/سعر)
- ⬜ رفع الكروت للمنصة: إعادة استخدام `POST /network-owner/cards/upload`
- ⬜ فصل الحالتين: كرت مزامَن من الراوتر (جرد فقط `source=mikrotik`) مقابل كرت مطروح للبيع (يدخل محاسبة المنصة)

#### جديد من تحليل ميكرونت:
- ⬜ توليد كرت واحد أو عدة كروت مع: ربط بعميل، اختيار باقة من بروفايلات الراوتر، قيود استهلاك وصلاحية (رصيد GB/MB، وقت استهلاك ساعة/دقيقة، صلاحية بالأيام، سعر بيع بالريال)
- ⬜ إلزامية وجود قالب كرت قبل التوليد ("لا توجد قوالب — صمّم قالباً أولاً")
- ⬜ مصمم قوالب يدوي: اسم الشبكة، رقم تواصل، اسم الباقة، لونين مخصصين (palette ~20 لون)، حجم خط slider، معاينة حية للكرت (USER-PASS)
- ⬜ قوالب صورية جاهزة (صور تصاميم) + معرض قوالب محفوظة لكل شبكة + تعديل/حذف قالب
- ⬜ نقاط البيع تُعرض على صفحة دخول الهوتسبوت (اسم+موقع لكل نقطة)

### 2.4 المراقبة — ⬜
- ⬜ CPU/RAM/Uptime `/system/resource`
- ⬜ درجة الحرارة `/system/health`
- ⬜ المنافذ والترافيك `/interface` + monitor-traffic
- ⬜ الأجهزة المتصلة

#### جديد من تحليل ميكرونت:
- ⬜ بث مباشر لسرعة الإنترنت على لوحة التحكم (تحميل/رفع bps + رسم بياني + إيقاف/تحديث)
- ⬜ شارة عدادات: المتصلين الآن / بروباند متصل-كلي / يوزرات هوتسبوت / يوزرات مانجر
- ⬜ عداد الأجهزة المتصلة + عداد الجيران Neighbor
- ⬜ صحة الجهاز (Health) + موارد النظام (Resources) كشاشات مستقلة
- ⬜ Netwatch: مراقبة شبكة (IP/مضيف، نوع اختبار، مهلة، فاصل، تعليق، تفعيل)
- ⬜ الرسوم البيانية Graph: لكل واجهة، أنواع (حركة مرور/أخطاء/حزم)، سرعة تحديث
- ⬜ أدوات تشخيص: Ping، Bandwidth Test، Torch، Packet Sniffer (فلاتر واجهة/IP/منفذ/بروتوكول/عدد حزم)، Fetch (تحميل URL بهيدرز)
- ⬜ سجلات الميكروتك: عرض + بحث + فلتر أخطاء/تحذيرات + حذف الكل

### 2.5 شبكة وحماية متقدمة — ⬜ (قسم جديد من تحليل ميكرونت)
- ⬜ عناوين IP `/ip/address`
- ⬜ خادم/عملاء/مستأجري DHCP + مجموعات العناوين IP Pool + إيجار ثابت Static Lease
- ⬜ خادم DNS + إدخالات ثابتة + إحصائيات الكاش
- ⬜ المسارات Routes `/ip/route`
- ⬜ جدول ARP + إدخال ثابت (منشور Published)
- ⬜ قواعد NAT كاملة (srcnat/dstnat/masquerade/port-forward، بروتوكولات، منافذ، واجهات)
- ⬜ جدار الحماية: قواعد Filter (سلاسل input/output/forward، إجراءات، بروتوكولات، عناوين، منافذ، واجهات، حالات اتصال) + قواعد Mangle (علامة حزمة) + قوائم العناوين Address Lists (مدة انتهاء مرنة) + الاتصالات النشطة Conntrack + بروتوكولات Layer7 مع أمثلة جاهزة (youtube/facebook/instagram/whatsapp/pubg...)
- ⬜ قوائم الحظر والتجاوز Hotspot IP Bindings (محظور/تجاوز/عادي) + القائمة البيضاء/السوداء
- ⬜ Simple Queues: إضافة طابور (اسم، هدف، Max Limit، Limit At، Burst Limit، presets سرعة جاهزة)
- ⬜ منع مشاركة الإنترنت بالبلوتوث/Tethering عبر TTL=1 لكل واجهة
- ⬜ تفعيل/تعطيل سيرفرات الهوتسبوت ("تفعيل الشبكة مجاناً")

### 2.6 النظام والجهاز — ⬜ (قسم جديد)
- ⬜ إعادة تشغيل الراوتر مع تأكيد + عرض معلومات النظام
- ⬜ نسخ احتياطي/استعادة `/system/backup` + `/export` (تسمية تلقائية بالتاريخ)
- ⬜ مستخدمو النظام والمجموعات `/user` + `/user/group` مع سياسات الصلاحيات
- ⬜ الأجهزة المجاورة Neighbor/MNDP + إضافة جهاز يدوي (اسم/IP/MAC)
- ⬜ صفحات دخول Hotspot: رفع ZIP من الهاتف / متجر قوالب جاهزة (16+ صفحة) / تخصيص نصوص الصفحة (اسم الشبكة، واتساب، رسالة ترحيب، تنبيهات) + نقاط البيع والباقات المعروضة
- ⬜ تكامل Telegram خطوة-بخطوة: إنشاء بوت (دليل BotFather)، لصق Token، فحص اتصال، ضبط Chat ID، تفعيل ميزات الإشعارات وجدولة البلاغات

### 2.7 عملاء ومحاسبة محلية — ⬜ (قسم جديد — موجود في ميكرونت!)
- ⬜ سجل عملاء محلي (اسم/هاتف/ملاحظات) + عدادات (الإجمالي/الدين) + بحث
- ⬜ ربط الكروت/يوزرات PPPoE بالعملاء مع سعر
- ⬜ سجل مدفوعات: إضافة دفعة (عميل+مبلغ+ملاحظة) تحدّث رصيد العميل تلقائياً، إجمالي مدفوعات، آخر تحديث
- ⬜ لوحة مبيعات: رسم أسبوعي (آخر 7 أيام، منخفضة/متوسطة/عالية)، إجمالي الأسبوع، أفضل أيام البيع (مراكز 1-3)، أحدث العمليات
- ⬜ ربط مع نظام سايبر المحاسبي الموجود (التحويلات/المبيعات/العمولات) بدل بناء نظام موازٍ

### 2.8 Backend مساند — ⬜
- ⬜ جدول `routers` (user_id, ip, port, username_enc, password_enc, status, last_seen)
- ⬜ حقل `source` على جدول `cards` (manual / mikrotik) — migration additive
- ⬜ endpoints مساندة لمزامنة الكروت المولّدة على الراوتر

### 2.9 نظام الاشتراك والتحكم بالميزات — 🔶 (الكود مكتمل — ينتظر النشر على staging)
- ✅ Sprint 0: `EntitlementService` في التطبيق + Feature Registry — يعمل بـ allow-all أثناء التطوير كاملاً
- ✅ تغليف كل قسم/شاشة جديدة بفحص `isAllowed(featureKey)` — الإغلاق على مستوى القسم لا داخل الأزرار
- ✅ جدول `mikrotik_plans` (اسم/وصف/سعر/عملة/مدة أيام/ميزات JSON/تفعيل/ترتيب) — migration additive
- ✅ جدول `mikrotik_subscriptions` (user_id, plan_id nullable=تجربة, status: trial/active/expired/cancelled, starts_at/ends_at, payment_request_id)
- ✅ جدول `mikrotik_payment_requests` **منفصل تماماً عن طلبات شحن الزبائن** (user_id, plan_id, amount, sender_name, bank_account_id FK, transfer_receipt_number, receipt_image, status pending/approved/rejected, admin_note, reviewed_by/at)
- ✅ إعدادات `mikrotik.trial_days` (=14) + `mikrotik.enforce` (=0) + `mikrotik.free_features` (JSON) في `app_settings` — تُحرَّر من مورد AppSettings الموجود في Filament بلا تحديث تطبيق
- ✅ Paywall موحد `PremiumLockCard` بزر «ترقية الحساب» → شاشة الاشتراك + شريط تجربة/انتهاء في لوحة الراوتر (يظهر فقط عند تفعيل enforce)
- ✅ لوحة Filament: موارد الخطط + الاشتراكات + مدفوعات MikroTik (موافقة تُنشئ اشتراكاً نشطاً بمعاملة ذرّية / رفض بسبب)
- ✅ الدفع: مساران — خصم محفظة المالك (lockForUpdate + WalletLog debit بـ reference_type=mikrotik_subscription، بلا دفتر موازٍ) أو طلب تحويل بنكي/محفظة بنفس مسار الإيصال الموجود (اسم مودع + رقم سند + صورة إيصال مرفوعة + إشعار أدمن)
- ✅ API منفصل تحت `/network-owner/mikrotik/`: `plans` + `entitlements` + `subscribe` + `payments` — يعيد `status/trialing/active/plan/trial_ends_at/ends_at/features[]/enforce`
- ✅ التطبيق: `SubscriptionService` + `subscription_screen` (حالة + باقات + دفع محفظة + نموذج تحويل + سجل الطلبات) + `entitlementProvider` يجلب الحالة من الخادم ويطبقها — أي فشل اتصال يُبقي allow-all

### 2.10 ترتيب السبرنتات (قرار تنفيذي — يمنع الخلل)
0. طبقة Entitlement + Feature Flags (allow-all، صفر تغيير سلوكي)
1. المستخدمون: حالات/تعديل/حذف/تفعيل/قطع/جماعي
2. PPPoE + User Manager + الباقات
3. الكروت: عميل/قيود/قوالب/QR/طباعة/PDF/رفع للمنصة
4. المراقبة الحية + الأدوات (قراءة فقط)
5. الشبكة المتقدمة: NAT/فايروول/Queues/DHCP/DNS/ARP (أوامر كتابة → تأكيدات)
6. النظام: نسخ/استعادة/صلاحيات/صفحات هوتسبوت/Telegram
7. ~~عملاء/مدفوعات/مبيعات محلية~~ → **مؤجَّلة لمرحلة المحاسبة الشاملة** (لا يُبنى دفتر ديون موازٍ داخل MikroTik — تُنفَّذ مرة واحدة فوق بنية المحفظة/المعاملات القائمة وتربط كروت الراوتر تلقائياً)
8. Backend: `routers` + `source` للكروت + مزامنة
9. **تفعيل نظام الاشتراك** (قلب Entitlement من allow-all إلى فرض الخطط)
10. الوصول عن بُعد (API-SSL/DDNS → ريلاي VPN)

قواعد: كل ميزة خلف feature flag معطّلة في الإنتاج حتى اكتمالها • كل سبرنت يُختبر على `routeros_sim.py` ثم ADB على الجهاز • الشراء والمحفظة والمعاملات الحالية لا تُعدَّل نهائياً • التصميم: Design system بألوان هوية سايبر (أبيض/كحلي/أحمر، Cairo) أفضل من ميكرونت — مكونات موحدة، skeleton loading، empty states مصممة، RTL أصيل، dark mode.

### ملاحظة مرجعية — تسعير ميكرونت
- ميكرونت يعمل بنظام: تجربة مجانية محدودة → بريميوم $8/3شهور، $14/6شهور، $25/سنة (دفع إلكتروني Stripe أو تحويل كريمي مع رفع إيصال)
- بعض الميزات مقفلة خلف الاشتراك ("هذه الميزة تتطلب اشتراكاً نشطاً")
- ملاحظة: سايبر تتبع نموذج مختلف (عمولة على المبيعات عبر المنصة) — الاشتراك اختياري ويحتاج موافقة المالك

---

## 3) جودة وأمان — ⬜
- ⬜ تدقيق كل مكتبة قبل إدراجها (القائمة في `docs/vendor-audit.md`)
- ⬜ مراجعة: إحصائيات المالك تعرض gross وليس net — توحيد العرض عند إضافة أرباح جديدة
- ⬜ اختبار ADB live على جهاز فعلي بجانب النسخة الإنتاجية
- ⬜ اختبار عدم تأثر الإنتاج إطلاقًا (الـ staging معزول بقاعدة منفصلة)

---

## سجل الإنجاز

| التاريخ | المهمة | الحالة |
|---|---|---|
| 2026-10-01 | نسخ السورس إلى testapp + تهيئة Git + رفع main إلى SiberWiFi | ✅ |
| 2026-10-01 | إعداد .env للـ staging (DB جديدة + APP_KEY جديد) | ✅ |
| 2026-10-01 | هوية التطبيق التجريبي (.staging + اسم + baseUrl staging) | ✅ |
| 2026-10-01 | فحص المستودعات المرشحة (تراخيص + سكان أمني) | ✅ (`docs/vendor-audit.md`) |
| 2026-10-09 | مزامنة testapp مع آخر تحديثات السورس المعتمد (حذف حساب + صفحات قانونية + إصلاحات التطبيقات) + إعادة تخصيصات staging + بناء وتثبيت APK على الجهاز | ✅ |
| 2026-10-09 | **نشر backend على staging لايف**: التطبيق خارج public_html في `staging-app/`، docroot الدومين الفرعي `staging/` فيه index.php مخصص فقط — `composer install` + migrate كامل + TestAccountSeeder + حساب أدمن + ملفات FCM + `optimize:clear`. اختبار لايف: `/`, `/api/regions`, `/api/maintenance-mode`, تسجيل دخول عميل ومالك، لوحة `/admin` — الكل يعمل والإنتاج سليم | ✅ |
| 2026-10-09 | حسابات الاختبار على staging: عميل `700000001`، مالك `700000002`، عميل ثان `700000003`، أدمن `770000000` — كلمة المرور للجميع `123456` | ✅ |
| 2026-10-09 | حسابات إضافية بطلب المالك: مالك `778257546` (معتمد + شبكة)، عميل `777993833` (رصيد 5000) — كلمة المرور `123456` | ✅ |
| 2026-10-09 | لوحة Filament على staging: `https://staging.saiberwifi.net/admin` — `admin@staging.saiberwifi.net` / `123456` | ✅ |
| 2026-10-09 | **ميزة MikroTik داخل network_owner_app**: `router_os_client` 2.0.1 (MIT) — نموذج `MikrotikRouterConfig` + تخزين آمن (`RouterStore` عبر flutter_secure_storage) + `RouterOsService` (اتصال/اختبار/قراءة الموارد/مستخدمي Hotspot/الباقات/الجلسات/إضافة وحذف مستخدمين) | ✅ |
| 2026-10-09 | واجهات MikroTik بهوية التطبيق (أبيض/كحلي/أحمر، خط Cairo): قائمة الأجهزة، إعداد+اختبار اتصال، لوحة مراقبة (CPU/RAM/إصدار/مدة تشغيل/جلسات)، تبويبات مستخدمي Hotspot، توليد كروت دفعي + رفعها لـ `/network-owner/cards/upload` (idempotent) | ✅ |
| 2026-10-09 | محاكي RouterOS API على الكمبيوتر (`routeros_sim.py`, منفذ 8728, `dev`/`dev123`) + `adb reverse tcp:8728` — اختبار لايف كامل على الجهاز دون راوتر فعلي | ✅ |
| 2026-10-12 | تحليل 175 لقطة حقيقية لتطبيق ميكرونت (`testapp/app-micronet/`) — اكتشاف كتالوج ميزات كامل يقارب Winbox + محاسبة محلية + قوالب كروت + متجر صفحات هوتسبوت + تسعير اشتراك ($8/$14/$25) | ✅ |
| 2026-10-12 | توسعة `routeros_sim.py` v2: هوتسبوت/PPPoE/UserManager/Queues/NAT/فايروول/DHCP/DNS/ملفات/سجلات/بث ترافيك حي + تسجيل كل أوامر API الواردة (`routeros_cmd_log.txt`) — ميكرونت نفسه اتصل به بنجاح | ✅ |
| 2026-10-12 | **Sprint 0**: `feature_keys.dart` + `EntitlementService` (allow-all) + `entitlement_provider` + `FeatureGate` + `PremiumLockCard` بهوية سايبر — طبقة الاشتراك جاهزة، تُفعَّل في Sprint 9 | ✅ |
| 2026-10-12 | **Sprint 1**: إدارة مستخدمي Hotspot كاملة — تصنيف حالات (متصل/غير نشط/منتهي/معطّل) بعدادات وفلاتر، بحث، تحديد جماعي/حذف جماعي، تعديل/تفعيل/تعطيل/حذف، قطع جلسات، نموذج إضافة/تعديل، عمليات `set/enable/disable/remove/active-remove` في `RouterOsService` + `runRouterOp` + 7 اختبارات وحدة ناجحة | ✅ |
| 2026-10-12 | **Sprint 2**: PPPoE كامل (`/ppp/secret|active|profile` — عدادات متصل/غير متصل/معطل، نموذج بخدمة pppoe/pptp/l2tp/ovpn/sstp + عنوان بعيد + Routes، قطع جلسات) + User Manager (`/user-manager/user|profile` — إضافة مستخدم بحد أجهزة، باقات بسعر/صلاحية/uptime/أجهزة/رصيد/سرعة) + إدارة باقات Hotspot كاملة (إضافة/تعديل/حذف بسرعة رفع/تحميل، أجهزة، مهلة جلسة، سكربتات On-Login/On-Logoff) + مسارات `/mikrotik/pppoe` و`/mikrotik/user-manager` وروابط لوحة التحكم — تحليل نظيف، مثبّت على الجهاز | ✅ |
| 2026-10-12 | **Sprint 3**: منظومة الكروت — قيود استهلاك عند التوليد (رصيد GB/MB → `limit-bytes-total`، وقت ساعة/دقيقة → `limit-uptime`، صلاحية أيام + سعر مشفّرين في التعليق `v:Nd p:N`) • `CardTemplate` (يدوي: لونان من 20+اسم شبكة+تواصل+باقة+سعر+حجم خط بمعاينة حية / صوري: صورة من المعرض + طبقة كود) • `CardTemplateStore` لكل راوتر • `VoucherCardView` بـ QR (رابط تسجيل دخول اختياري `{code}`) • `VoucherPrintService` (pdf+printing — شبكة 3×4 لكل A4 بخط Cairo وQR أصلي، طباعة عبر نظام أندرويد أو مشاركة PDF) • إلزامية القالب قبل الطباعة + معاينة شبكية للكروت المولّدة • شاشة `card_templates_screen` ومسار `/mikrotik/card-templates` — تحليل نظيف، مثبّت على الجهاز | ✅ |
| 2026-10-12 | مهمة معلّقة ضمن الطباعة: طباعة حرارية مباشرة ESC/POS تحتاج حزمة نقل (esc_pos_printer/bluetooth) — تُدقّق في `vendor-audit.md` قبل الإدراج؛ حالياً الطباعة عبر PDF تغطي كل الطابعات | ⬜ |
| 2026-10-12 | **Sprint 4**: شاشة «المراقبة والأدوات» بست تبويبات — بث مباشر (رسم rx/tx حي بـ fl_chart عبر `monitor-traffic once` كل 1.5ث على اتصال ثابت + إيقاف/بدء) • صحة الجهاز (موارد + حرارة/جهد/مراوح مع معالجة عدم توفر المستشعرات) • الأجهزة والجيران (عدادات متصل/جار/إيجار + قوائم MNDP وHotspot Hosts) • Netwatch (قائمة+إضافة بأنواع simple/icmp/tcp-conn/http-get+تفعيل/إيقاف+حذف) • السجلات (بحث+فلتر أخطاء+الأحدث أولاً) • أدوات (Ping بعدد مخصص بنتائج seq/وقت + Fetch بـ GET/POST/PUT/HEAD بنتيجة الحالة) — الخدمة: monitorOnce/interfaceDetails/health/neighbors/hosts/leases/logs/ping/fetch/netwatch CRUD — المحاكي وسّع (جيران+hosts+netwatch+fetch+ping متعدد الردود) — تحليل نظيف، مثبّت على الجهاز | ✅ |
| 2026-10-12 | **Sprint 5**: «الشبكة المتقدمة» — معمارية مواصفات تعريفية (section specs) تشغّل شاشة جدول عامة واحدة لكل جداول الراوتر بدل شاشة لكل جدول • **17 قسماً**: عناوين IP، مسارات، خوادم/عملاء/إيجارات DHCP (إيجار ثابت)، مجموعات عناوين، DNS ثابت، ARP (منشور=IP ثابت)، **NAT** (srcnat/dstnat بكل الإجراءات ومنافذ وواجهات)، **فلتر** (سلاسل+إجراءات+حالات اتصال)، **Mangle** (علامات حزمة/اتصال/توجيه+TTL)، **قوائم عناوين** (مدد انتهاء عربية)، **Layer7** مع 7 تعابير جاهزة (يوتيوب/فيسبوك/انستقرام/واتساب/تليجرام/تيك توك/PUBG)، اتصالات نشطة، حظر/تجاوز Hotspot، **Simple Queues** مع presets سرعة، سيرفرات هوتسبوت (تفعيل/تعطيل)، **حجب Tethering** لكل واجهة عبر قاعدة mangle TTL=1 موصوفة `saiber-ttl-block-` • قوائم منسدلة ديناميكية (واجهات/مجموعات محمولة من الراوتر) + نموذج add/edit موحد + بحث + تعطيل/تفعيل/حذف مع تأكيد — خدمة `table/add/set/remove/enable/disable` عامة — المحاكي وسّع بـ 12 جدولاً جديداً — تحليل نظيف، مثبّت على الجهاز | ✅ |
| 2026-10-12 | **Sprint 6**: شاشة «النظام» بست تبويبات — الجهاز (معلومات + إعادة تشغيل مؤكدة مع معالجة قطع الاتصال كحالة نجاح) • **النسخ الاحتياطي** (إنشاء بنمط اسم بالتاريخ + قائمة من `/file` + استعادة مؤكدة + تصدير .rsc) • **المستخدمون والمجموعات** (تبويبان: CRUD مستخدمي النظام باختيار مجموعة + مجموعات صلاحيات بـ 13 سياسة chips) • **المجدولات والسكريبتات** (إضافة مجدولة/سكريبت + تشغيل سكريبت يدوي + إيقاف/حذف) • **صفحات الهوتسبوت** (تحرير html-directory + login-by + كوكيز لكل بروفايل سيرفر + عرض ملفات hotspot على الراوتر + ملاحظة FTP معلّقة) • **Telegram** (Token+Chat ID في التخزين الآمن + إرسال رسالة تجريبية عبر api.telegram.org) — المحاكي وسّع (sys_users/sys_groups/hs_profiles/backup-load/script-run) — تحليل نظيف، مثبّت على الجهاز | ✅ |
| 2026-10-12 | مهمة معلّقة ضمن النظام: تحميل/رفع ملفات (نسخ .backup وقوالب صفحات ZIP) يتطلب عميل FTP — RouterOS API لا ينقل محتوى الملفات؛ يُدقّق `ftpconnect` في `vendor-audit.md` قبل الإدراج | ⬜ |
| 2026-10-12 | **Sprint 7**: تلميع نهائي — `ui_states.dart` موحّد (LoadingState/EmptyState/ErrorRetry) مطبَّق في شاشات المراقبة والشبكة والنظام بدل التكرار المحلي • اختبارات وحدات جديدة `card_template_test.dart` (تسلسل JSON + استبدال {code} في QR + قائمة ترميز/فك بمقاومة التلف) 4/4 • إجمالي الاختبارات 17 ناجحة — الفاشل الوحيد اختبارا `maintenance_mode` مسبقان غير متعلقين بالمايكروتك (يعجزان عن إيجاد أيقونة في شاشة الصيانة) • إصلاح أخطاء تحليل `use_null_aware_elements` — تحليل نظيف، مثبّت على الجهاز | ✅ |
| 2026-10-12 | مهمة معلّقة: اختبارا `maintenance_mode_test` يفشلان منذ ما قبل أعمال MikroTik (مشكلة في شاشة الصيانة نفسها — أيقونة مفقودة في واجهة الويدجت) — يحتاج فحصاً منفصلاً | ⬜ |
| 2026-10-15 | **Sprint 8** (ربط المنصة — باك إند إضافي، بلا مساس بأي جدول مالي): هجرة `mikrotik_routers` (user_id FK، host/api_port/username مفتاح فريد للـ upsert، api_password مشفّر، network_id اختياري، identity/board/version/عدادات هوتسبوت/uptime/last_seen) + هجرة `cards.source` (`platform`/`mikrotik`) و`cards.router_id` و`cards.meta` (JSON: limit_uptime/limit_bytes_total/validity_days/price/template_name/batch) • `NetworkOwnerMikrotikController`: `GET /routers`، `POST /routers/sync` (upsert لا ينشئ مكررات)، `DELETE /routers/{id}` — كلها تحت `can:network_owner` • رفع الكروت يقبل الآن `source`/`router_id`/`meta` مع التحقق من ملكية الراوتر والشبكة — `insertOrIgnore` يحفظ عدم التكرار • `MikrotikRouterResource` في Filament (قائمة+تعديل، كلمة مرور الراوتر مخفية دائماً) — فحص php -l نظيف | ✅ (منشور على staging 2026-10-26) |
| 2026-10-26 | **نشر Sprint 8 على staging + تصحيحات حرجة**: تسجيل مسارات `/network-owner/mikrotik/*` (routers sync/index/delete + entitlements/plans/subscribe/payments) — كانت غير مسجلة أصلاً • هجرة إصلاحية `2026_10_26_000001_ensure_mikrotik_columns_on_cards_table` (hasColumn guards) لأن `cards` على staging فقدت source/router_id/meta بعد إعادة بناء القاعدة • `NetworkOwnerCardController::upload` يقبل الآن `source`/`router_id`/`meta`/`items[]` مع تحقق ملكية الراوتر • نموذج `Card` يضم `router()` + cast meta | ✅ |
| 2026-10-26 | **استيراد كروت الراوتر — اختبار لايف ناجح**: شاشة «استيراد من الراوتر» تجلب مستخدمي Hotspot (TEST1234/GUEST01/OLD-USER) من المحاكي • تحديد+اختيار شبكة/فئة تلقائي • الإرسال عبر `items[]` بـ meta.profile لكل كرت • تحقق من القاعدة: 3 كروت `source=mikrotik` + `router_id=2` + meta صحيحة — بلا أي قيد مبيعات/معاملة • **Idempotency مؤكدة**: إعادة الرفع أعادت `uploaded=0, skipped=3` دون تكرار | ✅ |
| 2026-10-26 | إصلاح الشاشة الحمراء: `mikrotikRouterFromExtra` يفك extra ككائن أو Map مُستعاد (restoration/refresh) على كل مسارات `/mikrotik/*` + `_MissingRouterScreen` بدل الانهيار + `==/hashCode` على id لثبات family providers • شاشة الاستيراد: تذكير بالشبكة/الفئة عند النقر، اختيار تلقائي للخيار الوحيد، invalidate للقوائم عند الفتح، تنبيه عند غياب الشبكات | ✅ |
| 2026-10-26 | بيانات اختبار staging: شبكة+فئة لكل من `778257546` (SW-TEST-91) و`700000002` (SW-TEST-102) + ضبط كلمة مرور الأول `123456` + زرع 3 خطط اشتراك (أساسي/احترافي/كامل بميزات JSON) + تجربة 14 يوم بدأت تلقائياً + مزامنة الراوتر سجّلت id=2 | ✅ |
| 2026-10-15 | التطبيق: `remoteId` في `MikrotikRouterConfig` + `RouterSyncService` (مزامنة best-effort بعد كل اتصال ناجح — كلمة مرور الراوتر تبقى على الجهاز ولا تُرسل للخادم) + رفع الكروت يرسل `source:mikrotik` + `router_id` + `meta` بالقيود — تحليل نظيف، اختبارات 11/11، مثبّت على الجهاز | ✅ |
| 2026-10-15 | خطوة نشر معلّقة: `php artisan migrate` على قاعدة staging لتفعيل `mikrotik_routers` + أعمدة `cards` — الملفات جاهزة، الـ backend المحلي بلا vendor | ✅ (نُفّذت 2026-10-17) |
| 2026-10-16 | **Sprint 9 — الاشتراكات (باك إند إضافي بالكامل)**: 4 هجرات مرتّبة (`mikrotik_plans` → `mikrotik_payment_requests` → `mikrotik_subscriptions` → seed إعدادات app_settings: trial_days=14، enforce=0، free_features) • `NetworkOwnerMikrotikSubscriptionController`: entitlements يُنشئ تجربة 14 يوماً تلقائياً عند أول دخول ويحدّث المنتهية، دفع محفظة بمعاملة + lockForUpdate + WalletLog debit (reference_type=mikrotik_subscription — بلا دفتر موازٍ)، طلبات تحويل منفصلة عن شحن الزبائن (نفس حقول الإيصال: اسم مودع إجباري + رقم سند + صورة مرفوعة + إشعار أدمن، طلب معلّق واحد فقط) • 3 موارد Filament (خطط بـ CheckboxList ميزات عربية، اشتراكات، مدفوعات بموافقة/رفض ذرّي) + الإعدادات قابلة للتحرير من مورد AppSettings • كل مسارات `/network-owner/mikrotik/*` تحت `can:network_owner` — فحص php -l نظيف | ⏳ (ينتظر النشر على staging) |
| 2026-10-16 | التطبيق (Sprint 9): `subscription_service.dart` (نماذج + عملاء API) + `subscription_screen` على `/mikrotik/subscription` (بطاقة حالة، باقات، دفع محفظة بتأكيد، نموذج تحويل بصورة إيصال، سجل طلبات) + `entitlementProvider` يجلب الحالة من الخادم ويطبّق `applyServerState` مع بقاء allow-all عند أي فشل/عدم نشر + زر «ترقية الحساب» في PremiumLockCard + شريط تجربة/انتهاء في لوحة الراوتر يظهر فقط عند enforce=1 — تحليل نظيف، اختبارات 11/11، بناء APK ناجح | ⏳ (التثبيت معلّق — الجوال غير موصول) |
| 2026-10-17 | **نشر Sprint 8+9 على staging**: رفع 26 ملفاً عبر SSH/SFTP إلى `staging-app` (`tools/deploy_mikrotik_sprints.py`) + `optimize:clear` + `migrate --force` — الست هجرات نفّذت [Ran] • تحقق لايف بحساب مالك `700000002`: `entitlements` أنشأ تجربة 14 يوماً تلقائياً (trial_ends_at 2026-10-31) + `enforce=false` + 18 ميزة • `plans` يعيد إعدادات التجربة والميزات المجانية • `routers/sync` upsert صحيح (created→ثم false مع تحديث العدادات) + list + delete — كلمة مرور الراوتر لا تُرجَع أبداً | ✅ |
| 2026-10-16 | خطوات متبقية لـ Sprint 9: إنشاء باقة أولى من Filament + اختبار subscribe/payments بحساب مالك staging + عند التحقق قلب `mikrotik.enforce` إلى 1 من AppSettings | ⬜ |
| 2026-10-17 | **Sprint 10 — الوصول عن بُعد**: شاشة `/mikrotik/remote-access` مغلّفة بـ FeatureGate(`mikrotik.remote_access`) — بطاقات متدرجة: **DDNS** (`/ip/cloud` قراءة dns-name/public-address/status + تفعيل/إيقاف ddns-enabled) • **خدمة API-SSL** (`/ip/service` تعديل المنفذ + قيد عناوين المصدر + تفعيل/تعطيل) • **شهادة TLS** (إنشاء `saiber-api-ssl` موقعة ذاتياً add+sign + ربطها بالخدمة) • **قاعدة فايروول** (input/tcp/dst-port بوسم `saiber-remote-api` مع كشف الوجود) • **ملف اتصال عن بُعد** (يحفظ `MikrotikRouterConfig` جديداً بنفس بيانات الاعتماد + host=DDNS + useSsl=true ثم يختبر الاتصال فعلياً ويبلّغ النتيجة) • صندوق إرشادات أمان — الخدمة: cloudStatus/setCloud/ipServices/setIpService/certificates/addCertificate/signCertificate — المحاكي وسّع (`ip_cloud` + جداول services/certificates حقيقية + `/certificate/sign`) — تحليل نظيف، مثبّت على الجهاز + adb reverse مُعاد | ✅ |
| 2026-10-01 | استخراج وتحليل مستند API الشحن | ✅ (`API/api_text.txt` في المشروع الأصلي) |
