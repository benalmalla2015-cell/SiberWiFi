# CyberNet — خريطة المشروع وبيانات الوصول

> وثيقة داخلية سرية. تسرد *أين* تعيش كل مكوّن وبيانات الوصول —
> لا تسرد قيم الأسرار نفسها إطلاقاً. أي قيمة ظهرت في محادثة أو
> مخرجات طرفية تعتبر **مكشوفة** وتُدوَّر فوراً (قائمة التدوير أدناه).

## 1) مسارات السورس كود

| المكوّن | المسار |
|---|---|
| جذر المشروع | `C:\Users\HP\Desktop\saiberwifi` |
| تطبيق المشترك (Flutter) | `testapp\cyber_client_app` |
| الباكند (Laravel) | `testapp\backend` |
| حزمة RADIUS (Docker) | `testapp\cyber-radius` |
| شهادات PKI (CA + clients) | `testapp\cyber-radius\pki` — محلياً فقط |
| قوالب MikroTik | `testapp\cyber-radius\host-templates` |
| الملف المولّد للمضيف | `host-templates\generated\almalla-v6-001.rsc` — **يحوي shared secret** |
| الخطة والسجلات | `testapp\cyber_plan` |
| سكربت البناء الآمن | `testapp\tools\build_cyber_release.ps1` |
| API محلي للتجارب | `testapp\tools\cyber_local_api.php` |

## 2) بيانات الوصول — أين تعيش (لا قيم هنا)

| الوصول | مكان التخزين | الحالة |
|---|---|---|
| SSH للـVPS | مدير كلمات المرور لدى المالك فقط | ⚠️ تعرّض في الطرفية → **دوّر** |
| MySQL الخادم | `backend\.env` (gitignored) | ⚠️ محلي SQLite للتجربة |
| RADIUS shared secret | `cyber-radius\.env` + داخل `.rsc` المولّد | ⚠️ ظهر في مخرجات → **دوّر** |
| مفتاح CA الخاص | `cyber-radius\pki\ca\private\ca.key` | gitignored، على VPS + محلي |
| ملفات P12 العملاء | `pki\clients\{sim}\` + `backend\storage\app\private\cyber\certs\` | gitignored |
| كلمة سر P12 | اتفاقية `cyber{sim}` مؤقتة للتجربة | ⚠️ معروفة → تُستبدل بعشوائية عند الإصدار الحقيقي |
| Firebase config | `AppConfig` (معرف تطبيق — ليس سراً حرجاً) | مقبول مؤقتاً |
| CYBER_HMAC_KEY | `%USERPROFILE%\.cyber-build-secrets.psd1` + `CYBER_HMAC_KEY` في env الخادم | ✅ خارج المستودع |
| توقيع الإصدار | `CYBER_SIGN_SHA256` في ملف الأسرار أعلاه | ✅ خارج المستودع |
| Keystore الإصدار | لدى المالك — **لم يُنشأ بعد** | ⏳ قبل النشر على Play |

## 3) خطة الولوج للـVPS (تقوية موصى بها)

1. `PasswordAuthentication no` + مفاتيح SSH فقط، `PermitRootLogin no`
2. `ufw`: 22 محدود بـIP المالك، 1812/1813 UDP مفتوحة لـIP المضيف فقط
3. `fail2ban` على SSH + تسجيل auth منفصل
4. مستخدم خدمة `cyber` بلا shell بدل التشغيل كـroot
5. نسخ احتياطي مشفر لـ`pki/ca` خارج الخادم
6. قيود `clients.conf`: NAS بـIP واحد بدل `0.0.0.0/0`

## 4) قائمة تدوير الأسرار (كل ما ظهر في المحادثات)

- [ ] كلمة سر/مفتاح SSH للـVPS
- [ ] RADIUS shared secret (في `.env` وفي `.rsc` وعند المضيف)
- [ ] كلمات سر P12 الصادرة تجريبياً
- [ ] كلمة سر MySQL
- [ ] إعادة فحص `git log -p` لأي تسريب تاريخي — `git grep` على كامل التاريخ

## 5) ما لا يُشارَك مع أي طرف ثالث — أبداً

ملفات `pki/` كاملة، `.env` كلها، `.rsc` المولّد، Keystore،
ملف `.cyber-build-secrets.psd1`، قاعدة بيانات بها بيانات مشتركين،
ولقطات شاشة تحوي أرقاماً/رصيداً حقيقياً عند الإطلاق.

## 6) مشاركة آمنة لنماذج ذكاء أخرى

الأبيض الآمن: ملفات `lib/` و`app/` بلا `.env`، العقود البرمجية
(`routes/cyber/*.php`)، `SECURITY_TEST_BRIEF.md`، تقرير
`SECURITY_AUDIT_HOST.md` العام — ودائماً نسخة معدّلة منزوعة الأسرار.
لا يُرفع المستودع كاملاً لأي خدمة خارجية.
