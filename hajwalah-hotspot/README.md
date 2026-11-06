# شبكة هجولة — تصميم صفحات MikroTik Hotspot (RouterOS v6)

تصميم متكامل (RTL / Mobile-First) لبوابة الدخول، متوافق بالكامل مع **RouterOS v6** (يعمل أيضاً على v7 — الفروقات موضحة بالأسفل).

| الملف | الوظيفة |
|---|---|
| `login.html` | صفحة الدخول: كرت شحن بدخول تلقائي + حساب مشترك + Trial |
| `status.html` | حالة الجلسة: المدة، التحميل/الرفع، الوقت المتبقي، IP |
| `rlogin.html` | نافذة الحالة المصغّرة (Popup بعد الدخول) |
| `logout.html` | تأكيد تسجيل الخروج |
| `alogin.html` | «أنت متصل بالفعل» مع تحويل تلقائي للحالة |
| `flogin.html` | نسخة الإطار — تحويل لـ login.html |
| `radvert.html` | صفحة الإعلان الدوري (إن فعّلت advertise) |
| `error.html` | صفحة الخطأ العامة |
| `redirect.html` | التحويل بعد نجاح الدخول |
| `errors.txt` | ترجمة عربية لرسائل أخطاء الراوتر |
| `md5.js` | تشفير MD5 لمصادقة CHAP (Paul Johnston — المعياري) |
| `js/app.js` | منطق الدخول التلقائي والتبويبات وCHAP |
| `css/style.css` | التصميم المتجاوب كاملاً |
| `img/` | الشعار والبانر والأيقونة (SVG خفيفة، بلا موارد خارجية) |

## أبرز الميزات

- **اختيار السرعة بقائمة منسدلة**: المستخدم يختار الباقة (سهم/صاروخ/هجولة برو) وتُرسل مع طلب الدخول بحقل `plan` — يتجاهلها RouterOS تلقائياً ويمكن لنظام الكروت/RADIUS الخارجي قراءتها. الاختيار يُحفظ في `localStorage` للزيارات القادمة. عدّل الخيارات في وسم `<select id="plan">` داخل `login.html`.
- **دخول تلقائي بالكرت**: عند اكتمال رقم الكرت (افتراضياً 8 خانات — عدّل `VOUCHER_LEN` في `js/app.js`) يُسجَّل الدخول مباشرة دون ضغط زر. يدعم أيضاً تمرير الكرت بالرابط `?v=CODE` أو `#CODE`.
- **أمان**: تشفير كلمة المرور بـ CHAP/MD5 تلقائياً عندما يوفّر الراوتر `chap-id/chap-challenge`، ودعم HTTPS الكامل.
- **متجاوب بالكامل**: من 320px حتى سطح المكتب، حقول لمس كبيرة، واحترام `prefers-reduced-motion`.
- **بدون اعتماديات خارجية**: لا خطوط ولا CDN — تعمل كل الموارد قبل تسجيل الدخول دون تعديل Walled Garden.
- **وضع معاينة**: عند فتح الملفات خارج الراوتر تظهر شارة «وضع المعاينة» وبيانات تجريبية بدل متغيرات `$(...)`.

## الرفع إلى المايكروتيك (RouterOS v6)

1. فعّل FTP مؤقتاً أو استخدم نافذة Files في Winbox لرفع كل المحتويات إلى مجلد `hotspot` في جذر ملفات الراوتر:
   ```
   /ip service set ftp disabled=no
   ```
   بعد الرفع ارفع مجلد `hotspot` كاملاً (صفحات + css + js + img + md5.js + errors.txt).

2. تأكد أن البروفايل يشير للمجلد الصحيح:
   ```
   /ip hotspot profile set hsprof1 html-directory=hotspot
   ```

3. المعاينة بدون راوتر: افتح `login.html` مباشرة في المتصفح — سيعمل بوضع المعاينة.

## تفعيل HTTPS بين الصفحة والمايكروتيك (v6)

1. استورد شهادة (Let's Encrypt أو موقعة) عبر Files ثم:
   ```
   /certificate import file-name=server.crt
   /certificate import file-name=server.key
   /certificate print
   ```
2. اربط الشهادة ببروفايل الهوتسبوت وفعّل https:
   ```
   /ip hotspot profile set hsprof1 ssl-certificate=server.crt_0 login-by=https,http-chap
   ```
   > في RouterOS v6 خاصية `ssl-certificate` موجودة في **profile** وليس في server.
3. فعّل خدمة الويب الآمنة (لواجهة الإدارة أيضاً):
   ```
   /ip service set www-ssl certificate=server.crt_0 disabled=no
   ```
   مع `login-by=https` تُشفَّر بيانات الدخول كاملة عبر TLS، ومع `http-chap` تُشفَّر كلمة المرور بـ MD5 عبر `md5.js` المرفق.

> **RouterOS v7**: نفس الملفات تعمل، لكن الشهادة تُربط بالسيرفر:
> `/ip hotspot set [find] ssl-certificate=...`

## التحكم بالسرعات والكروت (v6)

أنشئ بروفايلات بحدود `rate-limit` ثم أضف الكروت كمستخدمين:

```
/ip hotspot user profile add name=card-4m  rate-limit=4M/4M
/ip hotspot user profile add name=card-10m rate-limit=10M/10M
/ip hotspot user profile add name=card-20m rate-limit=20M/20M
/ip hotspot user add name=HK8F2A1B password=HK8F2A1B profile=card-10m
```

حدّد طول الكرت الفعلي في `VOUCHER_LEN` أعلى `js/app.js`، وعدّل خيارات الباقات في `<select id="plan">` داخل `login.html` بما يطابق كروتك.

## ملاحظات v6

- لا تضع موارد خارجية (خطوط Google، CDN) — لن تُحمَّل قبل تسجيل الدخول.
- صفحات v6 المعيارية كلها موجودة في هذا المجلد — أي ملف ناقص سيعرض نسخة الراوتر الافتراضية.
- `errors.txt` يترجم رسائل الأخطاء تلقائياً في صفحة الدخول.
