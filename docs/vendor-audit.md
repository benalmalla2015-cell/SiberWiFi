# تدقيق المستودعات المرشحة — تقرير الأمان والتراخيص

تاريخ الفحص: 2026-10-01 | طريقة الفحص: استنساخ فعلي + قراءة السورس سطرًا بسطرًا + فحص LICENSE وpubspec
النسخ المحفوظة: `C:\Users\HP\Desktop\saiberwifi\vendor_audit\repos\` (خارج المستودع — مرجع فقط)

## النتيجة النهائية

| الحزمة | الإصدار | الترخيص (من ملف LICENSE) | تجاري؟ | القرار |
|---|---|---|---|---|
| `router_os_client` | 2.0.1 | **MIT** ©2024 Shafiq Sadat | ✅ | ✅ **SAFE-TO-USE** — طبقة الاتصال الأساسية |
| `routeros_api` | 0.1.4 | **MPL-2.0** | ✅ بشرط* | 🔶 USE-WITH-CAUTION — بديل احتياطي فقط |
| `mikrotik_mndp` | 0.0.4 | **MIT** ©2024 Hector Oliveros | ✅ | 🔶 USE-WITH-CAUTION — اختياري للاكتشاف التلقائي |
| `esc_pos_utils_plus` | 2.0.4 | **BSD-3** ©2020 Andrey U. | ✅ | ✅ **SAFE-TO-USE** — الطباعة الحرارية |
| `pdf` / `printing` (pub.dev) | latest | Apache-2.0 | ✅ | ✅ قياسي — تصدير PDF |
| `qr_flutter` (pub.dev) | latest | BSD-3 | ✅ | ✅ قياسي — QR للكروت |

## تفاصيل الفحص الأمني

### router_os_client — ✅ نظيف
- الملفات: `router_os_client.dart` (683 سطر — سورس وحيد)
- الاتصال: `Socket.connect` / `SecureSocket.connect` **إلى العنوان الذي يمرره المستخدم فقط** — لا مضيف ثابت
- التبعيات: `convert` (BSD-3)، `logger` (MIT) — لا http/dio
- لا eval، لا تحميل كود، لا تتبع، لا وصول لملفات الجهاز
- ملاحظة: `onBadCertificate: (_) => true` في SSL — مقبول لشهادات الراوترات ذاتية التوقيع

### routeros_api — 🔶 نظيف لكن حذر
- الملفات: `routeros_api_base.dart` (432 سطر — تمت قراءته كاملًا)
- نظيف تقنيًا: صفر تبعيات، socket للمضيف المُمرَّر فقط، تطبيق سليم لبروتوكول RouterOS (word-length encoding, !re/!done/!trap, heartbeat, auto-reconnect, streaming)
- ⚠️ أسباب الحذر (ليست أمنية بل تشغيلية): مستودع جديد (~10 commits، 0 نجوم)، ناشر غير موثق، README يقترح تبعية `git:` (HEAD غير مثبت)
- ⚠️ ترخيص MPL-2.0: copyleft على مستوى الملف — أي تعديل على ملفات الحزمة نفسها يجب نشره (الاستخدام كتبعية دون تعديل مسموح تجاريًا)
- ⚠️ يرسل كلمة المرور نصًا داخل القناة — آمن فقط مع SSL أو LAN موثوقة (هذا طبيعي للبروتوكول)
- القرار: بديل احتياطي؛ إن استُخدم يُثبَّت بـ commit SHA ويُعاد فحص lib/ قبل الشحن

### mikrotik_mndp — 🔶 نظيف وظيفيًا
- الملفات: `listener.dart`, `decoder.dart`, `message.dart`, `product.dart`, `product_info_provider.dart` (359 سطر — كلها مفحوصة)
- البث UDP `255.255.255.255:5678` = سلوك MNDP المتوقع (بروتوكول اكتشاف MikroTik الأصلي)
- `product_info_provider.dart` يقرأ `assets/products.json` **محليًا** — لا اتصال خارجي (الاشتباه السابق بوجود طلبات إلى mikrotik.com كان إنذارًا كاذبًا)
- ⚠️ `network_info_plus` يقرأ SSID/BSSID → يتطلب صلاحية location على Android
- ⚠️ غير محدَّث منذ ~سنتين — وظيفيًا بسيط لذا المخاطر محدودة

### esc_pos_utils_plus — ✅ نظيف
- الملفات: 17 ملف dart / ~2000 سطر في `lib/`
- **صفر شبكة**: لا http/dio/socket في `lib/` إطلاقًا (أكواد Socket الموجودة في `example/` فقط — لا تُشحن)
- التبعيات: `image` (BSD-3)، `html` (MIT)
- المستودع الصحيح: `kechankrisna/esc_pos_utils_plus`

## مستودعات مرفوضة (مرجع معماري فقط — لا يُنسخ منها كود)

| المستودع | السبب |
|---|---|
| `Uszkido/wirespot` | ترخيص "Other" — برنامج proprietary (Vexel Innovations)؛ CONTRIBUTING يمنع إعادة الاستخدام التجاري |
| `amolood/Mikrotik-flutter-app` | **بدون ملف LICENSE** — كل الحقوق محفوظة قانونيًا؛ مؤرشف ومتوقف |
| `laksa19/mikhmonv3` | GPL v2 — يجبر على نشر سورسنا إذا دمجنا كوده |

## قاعدة الفحص المستمرة
أي حزمة تُضاف مستقبلًا تمر بنفس الدورة: LICENSE فعلي → تبعيات وتراخيصها → سكان `lib/` كاملًا (URLs/sockets/eval/file access) → سجل القرار في هذا الملف.
