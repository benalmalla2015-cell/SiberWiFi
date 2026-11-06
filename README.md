# SiberWiFi — بيئة التطوير والتجربة

نسخة تطويرية منفصلة بالكامل عن بيئة الإنتاج. **لا يُستخدم هذا المجلد لتعديل كود الإنتاج.**

## أبرز الميزات المنفَّذة

### إدارة MikroTik (تطبيق أصحاب الشبكات + الباك اند)
- اتصال RouterOS API مباشر — دعم v6 (مصادقة MD5 القديمة) وv7، مع ترميز UTF-8 آمن ومعالجة `!fatal`
- شاشة مراقبة، مستخدمو Hotspot، User Manager (مع fallback لمسار v6 `/tool/user-manager`)
- توليد كروت: حتى **5000 كرت** دفعة واحدة عبر أوامر API متوازية، مع اختيار `rate-limit` من قائمة
- طباعة الكروت PDF — دعم عربي كامل (RTL) + QR + اسم الشبكة/السعر/التواصل
- **متجر قوالب صفحات الدخول**: 20 قالباً (5 أساسية + 15 جديدة: 9 مجانية + 6 مدفوعة premium)
  - تُقدَّم من السيرفر (`page-templates` API) — إضافة قالب جديد لا تحتاج تحديث APK
  - ميزات داخل القوالب: تبويب كرت/حساب، «تذكر بياناتي»، شارة سرعة، CHAP آمن
  - القوالب المدفوعة محمية سيرفرياً: تتطلب اشتراك `active` (403 لغير المشتركين)
- معاينة القوالب بقيم نموذجية (`preview.html`) بدل رموز `$(...)` الخام

### لوحة المشرف (Filament — staging.saiberwifi.net/admin)
- **مجموعة «المحاسبة»**: خطط + اشتراكات + طلبات دفع — موافقة/رفض مع إشعارات تلقائية وإنهاء الاشتراكات القديمة ضمن transaction
- **MikroTik**: خطط (18 ميزة قابلة للتقييد)، اشتراكات مع «منح اشتراك» يدوي وتعبئة تواريخ تلقائية، مراجعة مدفوعات، رواترات مسجلة
- **تحكم بميزات كل حساب**: `granted_features`/`revoked_features` على اشتراكات MikroTik والمحاسبة (الحظر يغلب المنح)
- إصلاحات بنيوية: أصول Filament، closures الحقن بالاسم/النوع، ترميز JSON المزدوج للميزات

### النظام المحاسبي (ACC)
- وحدات كاملة: مبيعات، مشتريات، مخزون، مصاريف، ديون، صناديق، تحويلات، وكلاء/موزعون، نقاط ولاء، خصومات، طلبات POS، تقارير، نسخ احتياطي، مزامنة offline
- فوترة اشتراكات المحاسبة عبر طلبات دفع يوافق عليها المشرف

### CyberNet
- مشتركون، باقات، جلسات، محافظ، تحويلات، عمولات وكلاء، RADIUS (`cyber-radius/` بمحرك Python + قوالب host)

## البنية

## البنية

```
testapp/
├── backend/            Laravel 12 + Filament — بيئة staging
├── customer_app/       تطبيق العميل (Flutter) — com.saiberwifi.customerapp.staging
├── network_owner_app/  تطبيق أصحاب الشبكات (Flutter) — com.saiberwifi.network_owner_app.staging
└── docs/
    └── ROADMAP.md      مستند المهام المرجعي (المنفَّذ والمتبقي)
```

## بيئة staging

- URL: `https://staging.saiberwifi.net` (المسار: `public_html/staging` على نفس الاستضافة)
- قاعدة بيانات منفصلة: `u170359695_staging` (انظر `backend/.env` — غير مرفوع لـ git)
- التطبيقات التجريبية تُثبَّت بجانب الإنتاجية دون تعارض (applicationId مختلف)

## نشر الـ backend على الاستضافة

1. ارفع محتوى `backend/` إلى `public_html/staging/`
2. انسخ `firebase-credentials.json` يدويًا (غير موجود في git)
3. على السيرفر: `composer install --no-dev` ثم `php artisan migrate` ثم `php artisan storage:link`
4. وجّه document root للدومين الفرعي إلى `staging/public`

## قواعد

- كل هجرة قاعدة بيانات additive فقط (لا تعديل/حذف أعمدة حالية)
- لا تُرفع أسرار — `.gitignore` يستثني `.env*` و`firebase/*.json` و`firebase-credentials.json`
- تفاصيل المهام والحالة: `docs/ROADMAP.md`
