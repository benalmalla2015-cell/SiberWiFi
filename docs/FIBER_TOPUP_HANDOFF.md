# تسليم مهمة: تفعيل «شحن رصيد فايبر» في تطبيق أصحاب الشبكات

> **مهمة المحادثة الأخرى**: استبدال شاشة `ComingSoonScreen` بشاشة دفع فايبر حقيقية
> تعيد استخدام البنية الخلفية الموجودة بالفعل. **الباك إند جاهز 100% —
> لا تعديل على أي ملف PHP نهائياً.**

---

## 1. مسارات السورس كود

### تطبيق أصحاب الشبكات (الهدف)
```
C:\Users\HP\Desktop\saiberwifi\testapp\network_owner_app\
├── lib\core\config\router.dart                     ← المسار /fiber-topup موجود
├── lib\features\dashboard\presentation\screens\dashboard_screen.dart  ← زر «شحن رصيد فايبر» موجود
└── lib\features\dashboard\presentation\screens\coming_soon_screen.dart ← الشاشة المؤقتة الحالية
```

### الباك إند المشترك (جاهز — لا تلمسه)
```
C:\Users\HP\Desktop\saiberwifi\testapp\backend\
├── app\Http\Controllers\Api\TopupController.php    ← services/quote/pay — يعالج كل شيء
├── database\seeders\TopupServiceSettingsSeeder.php ← باقات الفايبر الـ9 الرسمية موجودة
├── routes\api.php                                  ← النقاط مسجّلة تحت auth:sanctum
└── app\Filament\Resources\TopupServiceSettingResource.php ← تحرير الأسعار من لوحة الإدارة
```

### المرجع الذهبي — نفس الميزة في تطبيق العميل (مختبرة وتعمل)
```
E:\saiberwifi-archive\customer_app\lib\features\bills\
├── presentation\screens\topup_payment_screen.dart  ← الشاشة الكاملة: تبويبات + مجموعات + معاينة
├── data\topup_models.dart                          ← TopupService / TopupPackage models
└── presentation\providers\topup_provider.dart      ← Riverpod providers + quote family
```
انسخ المنطق منها وادمجه بالأسلوب المعماري الموجود في `network_owner_app`
(نفس go_router + Riverpod + dio patterns).

---

## 2. الوضع الراهن — لماذا المهمة بسيطة

الربط **موجود مسبقاً** في `router.dart` و`dashboard_screen.dart`:

```dart
// dashboard_screen.dart (موجود فعلاً)
label: 'شحن رصيد فايبر',
onTap: () => context.push('/fiber-topup'),   // الزر جاهز

// router.dart (موجود فعلاً)
GoRoute(
  path: '/fiber-topup',
  builder: (context, state) => const ComingSoonScreen(
    title: 'شحن رصيد فايبر',
    icon: Icons.bolt_rounded,
  ),
),
```

**المطلوب الوحيد**: إنشاء `FiberTopupScreen` جديد وتبديل الـ builder
في المسار الحالي — لا تضف مسارات جديدة ولا تعدّل الداشبورد.

---

## 3. عقد الـ API — كل شيء جاهز في الخادم

النقاط موجودة تحت `/api` بحماية `auth:sanctum` (التوكن نفسه للمالك):

### أ) جلب الكتالوج — `GET /api/topup/services`

يبحث عن الخدمة `"code": "post"` — كائنها:

```json
{
  "code": "post",
  "name_ar": "هاتف ثابت / ADSL",
  "provider_endpoint": "post",
  "account": "south",
  "fee_type": "none",
  "fee_value": "0.00",
  "meta": {
    "fields": [
      {"key": "num", "type": "number", "len": 8, "label": "رقم الهاتف الثابت"},
      {"key": "type", "type": "select", "label": "نوع الخدمة",
       "options": [{"value": "line", "label": "هاتف ثابت"},
                   {"value": "adsl", "label": "انترنت ADSL"},
                   {"value": "ftth", "label": "فايبر FTTH"}]}
    ],
    "amount_options": [250, 500, 1000, ...]
  },
  "packages": [ ... ]
}
```

### ب) باقات الفايبر الرسمية — القائمة الجديدة للاتصالات اليمنية

موجودة في `packages` مجمّعة حسب `group` — **14 باقة رسمية** حسب
ملصق الاتصالات اليمنية (الاتصال الصوتي مجاناً داخل الشبكة الثابتة لكلها):

| المجموعة | الباقة | code | السعر (ريال) |
|---|---|---|---|
| فايبر 10M | فايبر 36 جيجا — 10M | `ftth10-36` | 4,000 |
| فايبر 10M | فايبر 84 جيجا — 10M | `ftth10-84` | 8,000 |
| فايبر 10M | فايبر 177 جيجا — 10M | `ftth10-177` | 16,000 |
| فايبر 25M | فايبر 60 جيجا — 25M | `ftth25-60` | 6,600 |
| فايبر 25M | فايبر 140 جيجا — 25M | `ftth25-140` | 13,300 |
| فايبر 25M | فايبر 300 جيجا — 25M | `ftth25-300` | 27,000 |
| فايبر 50M | فايبر 140 جيجا — 50M | `ftth50-140` | 15,400 |
| فايبر 50M | فايبر 320 جيجا — 50M | `ftth50-320` | 30,400 |
| فايبر 50M | فايبر 670 جيجا — 50M | `ftth50-670` | 60,300 |
| فايبر 100M | فايبر 340 جيجا — 100M | `ftth100-340` | 37,400 |
| فايبر 100M | فايبر 780 جيجا — 100M | `ftth100-780` | 74,000 |
| فايبر 100M | فايبر 1500 جيجا — 100M | `ftth100-1500` | 140,000 |
| فايبر 100M | فايبر 3000 جيجا — 100M | `ftth100-3000` | 270,000 |
| فايبر 200M | فايبر 4000 جيجا — 200M | `ftth200-4000` | 400,000 |

> رتّب العرض في خمس مجموعات قابلة للطي حسب قيمة `group`
> (فايبر 10M / 25M / 50M / 100M / 200M) — نفس نمط تجميع شاشة العميل.
> كل باقة تحمل `params: {"type": "ftth"}` و`minutes: "مجاناً"` —
> **مرِّر `params` كما هي للخادم**، واعرض `data` + `minutes` كوصف فرعي.

### ج) المعاينة قبل الدفع — `GET /api/topup/quote`

```
GET /api/topup/quote?service=post&num=01123456&package=ftth25-140&gateway=south
```

الرد (مبادئه المهمة):
- `amount` → مبلغ المزود (13,300)
- `wallet_amount` → ما سيُخصم من المحفظة فعلاً (قد يختلف عند بوابة الشمال بفارق الصرف)
- `net`, `unit_price`, معلومات التحويل عند التبديل بين بوابات جنوب/شمال
- عرض قيمة `gateway` اختياري: `south` (افتراضي) أو `north`

### د) التنفيذ — `POST /api/topup/pay`

```json
{
  "service": "post",
  "num": "01123456",        // رقم الهاتف الثابت — 8 خانات
  "package": "ftth25-140",    // فقط الكود — الخادم يحسب السعر
  "gateway": "south"        // اختياري — يُستنتج من منطقة المستخدم افتراضياً
}
```

**قواعد أمان يفرضها الخادم تلقائياً** (لا حاجة لتنفيذها):
- السعر يُحسب من الخادم — لا ترسل `amount` أبداً مع `package`
- بوابة خاطئة لباقة مقيّدة → رفض برسالة عربية
- فشل المزود → استرداد تلقائي للمحفظة
- رصيد غير كافٍ → رسالة عربية

### هـ) سداد مبلغ حر (بدون باقة)

```json
{ "service": "post", "num": "01123456", "amount": 1000, "type": "line" }
```
- `type`: `line` (هاتف ثابت) | `adsl` (انترنت) | `ftth` (فايبر — يمرّر للمزود كما هو)

---

## 4. آلية التنفيذ — خطوات مقترحة بأمان كامل

1. **أنشئ مجلداً جديداً فقط** — صفر تعديل على ميزات قائمة:
   ```
   lib\features\fiber_topup\
   ├── data\fiber_topup_models.dart      ← نسخ topup_models.dart من العميل
   ├── presentation\providers\fiber_topup_provider.dart  ← جلب الخدمة + المعاينة
   └── presentation\screens\fiber_topup_screen.dart      ← الشاشة
   ```

2. **الشاشة تبني نفسها من الرد** — `meta.fields` ينتج الحقول ديناميكياً
   (رقم الهاتف 8 خانات + قائمة نوع الخدمة)، و`packages` تُعرض
   مجمّعة بقيمة `group` — **لا تكتب أسعاراً أو باقات يدوياً أبداً**.

3. **تدفق الدفع**: المستخدم يدخل الرقم → يختار باقة →
   `quote` يعرض مبلغ المزود + خصم المحفظة + فرق التحويل →
   تأكيد → `pay` → رسالة النجاح/الفشل العربية القادمة من الخادم كما هي.

4. **بدّل builder المسار الحالي فقط** في `router.dart` السطر ~168:
   ```dart
   builder: (context, state) => const FiberTopupScreen(),
   ```

5. **استخدم نفس عميل الـ API** الموجود في التطبيق (`dio`/http client
   الذي تستخدمه باقي الميزات) — تحقق من `lib/core/` لنمط الطلبات.

## 5. ممنوعات صارمة — حتى لا ينكسر أي شيء

- ❌ لا تعدّل أي ملف في `testapp/backend\` — الباك إند نهائي ومباشر
- ❌ لا تعدّل `dashboard_screen.dart` — الزر موجود ويعمل
- ❌ لا تضف مساراً جديداً — استخدم `/fiber-topup` الحالي
- ❌ لا ترسل `amount` مع `package` — الخادم هو المصدر الوحيد للسعر
- ❌ لا تفترض الباقات — اجلبها من `/topup/services` دائماً (الإدارة تعدّلها من Filament)
- ❌ لا تمس `coming_soon_screen.dart` — مسار `/starlink-topup` ما زال يستخدمه

## 6. التتبع والأرباح — جاهز في لوحة التحكم (منفّذ)

كل عملية دفع تُسجّل تلقائياً في جدول `topup_orders` مع `user_id` —
وهو مربوط بالمستخدم كاملاً، فكل صف يكشف تلقائياً:

- **اسم العميل ورقم جواله** (`user.name` + `user.phone`)
- **نوع الحساب**: `user.type` → `client` عميل | `network_owner` صاحب شبكة
- **المنطقة**: `user.region_type` → `south` جنوب | `north` شمال
- الخدمة + البوابة + الرقم المستهدف + المبلغ + العمولة + المخصوم + تكلفة المزود
- الحالة (`done/pending/failed/banned`) + `refunded` + `transid` + `provider_ref_id` + رد المزود الكامل

### مورد Filament الجديد (منشور على staging)

- `app/Filament/Resources/TopupOrderResource.php` — «عمليات الشحن الفوري»
  تحت مجموعة «الشحن الفوري»: جدول بفلاتر (حالة/خدمة/بوابة/**نوع حساب**/منطقة/فترة)
  + عمود ربح محسوب بأمان عملة-بعملة.
- `app/Filament/Widgets/TopupProfitStats.php` — إحصاءات في رأس القائمة:
  إجمالي عمولة جنوب وشمال (اليوم/الشهر)، عدد الناجحة/المعلّقة/الفاشلة/المستردة،
  وإيراد مبيعات الكروت + عدد المباع.
- قراءة فقط — لا حذف ولا تعديل يدوي، لحماية سجل التدقيق.

**مهمة المحادثة الأخرى هنا**: لا شيء — عمليات أصحاب الشبكات تظهر
تلقائياً بنوع «صاحب شبكة» بمجرد تنفيذهم الدفع عبر نفس `/topup/pay`.
إن أرادت عرض سجل العمليات داخل التطبيق نفسه فنقطة `GET /api/topup/orders`
جاهزة وتعيد طلبات المستخدم الحالي (آخر 100).

## 7. اختبار — حسابات جاهزة على staging

| الحساب | الرقم | كلمة المرور | المنطقة | الرصيد |
|---|---|---|---|---|
| مالك/عميل شمال | 700000002 | 123456 | الشمال | 18,000 ر.ش |
| عميل جنوب | 700000004 | 123456 | الجنوب — عدن | 150,000 ر.ج |

- نقطة الـ API على staging: `https://staging.saiberwifi.net/api`
- تحقق من `app_config.dart` في تطبيق المالك أن `baseUrl` يشير لنفس البيئة
- أرقام هاتف ثابت للاختبار: أي رقم 8 خانات (الدفع الفعلي يتطلب رصيد مزود —
  المعاينة `quote` مجانية وآمنة دائماً للاختبار)
