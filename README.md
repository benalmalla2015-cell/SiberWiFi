# SiberWiFi — بيئة التطوير والتجربة

نسخة تطويرية منفصلة بالكامل عن بيئة الإنتاج. **لا يُستخدم هذا المجلد لتعديل كود الإنتاج.**

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
