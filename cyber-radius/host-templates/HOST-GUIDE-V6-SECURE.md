# دليل المضيف v6 — التسليم المقوّى (جزءان)

> **تغيير جوهري:** الملف الآن جزءان. الملف الرئيسي لا يحوي أي سر —
> سرّ RADIUS في ملف `*-key.rsc` منفصل يُسلَّم بقناة مختلفة.
> سرّ مسروق من الملف الرئيسي = لا شيء؛ والسرّ الحقيقي لا يعمل إلا
> من IP المضيف الحقيقي (قيد خادمي `clients.conf`).

## للمنصّة (أنت) — خطوات التسليم

1. التوليد: `generate-host-v6.ps1 -HostId <id> -ServerIP <radius-ip>`
   ينتج `generated/<id>.rsc` + `secure/<id>-key.rsc` (سِرّ جديد).
2. الختم: `protect-host-file.ps1 -Seal <file>` لكل ملف ← ملفا `.enc`.
3. أرسل ملفي `.enc` لصديقك بأي قناة (واتساب/تليجرام/USB).
4. **كلمة الفكّ تُعطى شفهياً أو بمكالمة — لا تُكتب مع الملف أبداً.**
5. بعد نجاح اللصق: حدّث `clients.conf` على الـVPS بـIP المضيف الحقيقي.

## للمضيف (صديقك) — خطوات التنفيذ (~3 دقائق)

1. افتح PowerShell في مجلد الملفات ونفّذ لكل ملف:
   `.\protect-host-file.ps1 -Open almalla-v6-001.rsc.enc`
   وأدخل كلمة الفكّ ← يستعيد `.rsc` الأصلي مع تحقق سلامة.
2. Winbox ← New Terminal ← **الصق الملف الرئيسي كاملاً** ← Enter.
3. **الصق ملف المفتاح** (`*-key.rsc` — سطران فقط) ← Enter.
4. يظهر `CyberNet` في الشبكات اللاسلكية. تم.

## الحارس الذاتي (cyber-guard)

- سكربت مجدول كل 30 دقيقة داخل الراوتر يتحقق من وجود رابط المصادقة.
- إن حُذف/عُطّل ← يعطّل شبكات `cyber-ap` تلقائياً (فشل-مغلق) ويسجّل
  `cyber-guard: upstream removed` — لا واي فاي مفتوحة بلا محاسبة.

## التراجع الكامل (بلا مساس بشبكته)

```
/interface wireless remove [find name~"cyber-ap"]
/interface wireless access-list remove [find comment=cyber]
/interface wireless security-profiles remove [find name=cyber-sec]
/interface bridge port remove [find bridge=cyber]
/ip dhcp-server network remove [find gateway=10.99.0.1]
/ip dhcp-server remove [find name=cyber-dhcp]
/ip pool remove [find name=cyber-pool]
/ip address remove [find interface=cyber]
/interface bridge remove [find name=cyber]
/ip firewall nat remove [find comment=cyber]
/ip firewall filter remove [find comment=cyber]
/radius remove [find comment="cyber-upstream"]
/system scheduler remove [find name=cyber-guard]
/system script remove [find name=cyber-guard]
```
