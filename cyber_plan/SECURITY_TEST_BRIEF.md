# CyberNet — موجز اختبار أمني آمن للنماذج الأخرى

> **الغرض**: تمكين نموذج ذكاء آخر من مراجعة/اختبار الكود
> **دون** الوصول لأي سر أو بيانات إنتاجية. أرسل هذا الملف +
> المقتطفات المحددة فقط — لا ترسل المستودع كاملاً أبداً.

## ما يُشارَك (آمن)

- ملفات `lib/` و`app/` بعد حذف أي قيمة ترميزية مضمّنة
- ملفات `routes/cyber/*.php` — العقود والمنطق
- `WifiProfileChannel.kt`، `SecurityChannel.kt`، `api_guard.dart`
- هذا الموجز + `PLAN.md` (منزوع أرقام الهواتف/الأسرار)

## ما لا يُشارَك إطلاقاً

| العنصر | السبب |
|---|---|
| أي `.env` | كلمات سر قاعدة/خدمات |
| `cyber-radius/pki/**` | مفاتيح CA وعملاء خاصة |
| `*.p12` | هويات مشتركين مشفرة |
| `host-templates/generated/*.rsc` | RADIUS secret + IP حقيقي |
| قاعدة البيانات/التصديرات | بيانات KYC مشتركين |
| `.cyber-build-secrets.psd1` | مفاتيح التوقيع وHMAC |
| عناوين IP/نطاقات حقيقية | بصمة البنية التحتية |

## نطاق الاختبار المطلوب (OWASP)

### API / Backend (OWASP API Security Top 10 + ASVS L2)

- BOLA/IDOR: هل `sim_no`+`device_id` يمنعان فعلاً قراءة بيانات مشترك آخر؟
- Mass assignment في `register` و`bind` و`subscriptions`
- Rate limiting على `register`/`bind`/`topup` (brute-force)
- حقن SQL في استعلامات المحفظة/الاشتراكات
- التفاف `idempotency_key` (تكرار الطلب بنفس المفتاح → نفس النتيجة مرة واحدة)
- التحقق من HMAC: رفض توقيع مكسور/منتهي/بلا nonce
- حذف الحساب: هل تبقى وثائق هوية قابلة للوصول بعد `deleted_at`؟

### Mobile (OWASP MASVS / MASTG)

- هل تُسحب شهادة EAP-TLS فقط للجهاز المرتبط؟
- أين تُخزّن `sim_no`/`device_id` — SharedPreferences أم Keystore؟
- هل يمكن تعديل `AppConfig` وإعادة التوقيع دون أن يفشل gate؟
- هل حوار «لا شكراً» يفسد حالة الاقتراح أم يُستعاد؟
- هل يعمل التطبيق على جهاز rooted بلا تحذير (قبل STRICT_TAMPER)؟

### Infrastructure (CIS)

- هل `clients.conf` يقيد NAS بـIP واحد؟
- هل شهادة العميل تُبطل عند حذف الحساب؟ (revocation/CRL)
- هل يوجد تسجيل تدقيق لعمليات topup/subscribe؟

## تنسيق تقرير الاختبار المطلوب

لكل ثغرة: `severity (critical/high/med/low)` + `الملف:السطر` +
`خطوات الاستغلال` + `الإصلاح المقترح` — بلا كلام عام.
