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

### 2.3 الكروت — ⬜
- ⬜ توليد كرت واحد/دفعة على الراوتر
- ⬜ QR لكل كرت (`qr_flutter`)
- ⬜ طباعة حرارية ESC/POS (`esc_pos_utils_plus` — BSD)
- ⬜ تصدير PDF (`pdf`/`printing` — Apache-2.0)
- ⬜ قوالب تصميم الكرت (شعار/اسم شبكة/سعر)
- ⬜ رفع الكروت للمنصة: إعادة استخدام `POST /network-owner/cards/upload`
- ⬜ فصل الحالتين: كرت مزامَن من الراوتر (جرد فقط `source=mikrotik`) مقابل كرت مطروح للبيع (يدخل محاسبة المنصة)

### 2.4 المراقبة — ⬜
- ⬜ CPU/RAM/Uptime `/system/resource`
- ⬜ درجة الحرارة `/system/health`
- ⬜ المنافذ والترافيك `/interface` + monitor-traffic
- ⬜ الأجهزة المتصلة

### 2.5 ميزات إضافية — ⬜
- ⬜ صفحات Hotspot (رفع/تعديل قوالب)
- ⬜ نسخ احتياطي/استعادة `/system/backup` + `/export`
- ⬜ تنبيهات Telegram
- ⬜ إدارة عدة راوترات
- ⬜ الوصول عن بُعد: api-ssl بـ IP عام/DDNS (v1) — نفق VPN/ريلاي عبر السيرفر (v2)

### 2.6 Backend مساند — ⬜
- ⬜ جدول `routers` (user_id, ip, port, username_enc, password_enc, status, last_seen)
- ⬜ حقل `source` على جدول `cards` (manual / mikrotik) — migration additive
- ⬜ endpoints مساندة لمزامنة الكروت المولّدة على الراوتر

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
| 2026-10-01 | فحص المستودعات المرشحة (تراخيص + سكان أمني) | 🔶 |
| 2026-10-01 | استخراج وتحليل مستند API الشحن | ✅ (`API/api_text.txt` في المشروع الأصلي) |
