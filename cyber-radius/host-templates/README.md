# host-templates — قالب المضيف المعتم (CYB-02)

`host.rsc.tmpl` يتحوّل إلى ملف `.rsc` واحد لكل مضيف يُلصَق في Winbox
Terminal فيبثّ SSID `CyberNet` (WPA2-Enterprise←RADIUS) فوراً —
دون لمس أي إعداد قائم على الراوتر.

## ما يفعله الملف على راوتر المضيف
- بريدج `cyber` + DHCP خاص (`10.77.x.0/24`) و vAP باسم CyberNet على كل راديو.
- RADIUS (1812/1813) عبر نفق WireGuard + `radius incoming` للـ CoA (3799)
  + interim accounting كل دقيقة.
- قواعد جدار تُدخَل فوق قواعد المالك: عزل كامل عن شبكاته + إنترنت فقط.
- كل ما يُنشأ موسوم `comment=cyber` — إعادة اللصق تعيد بناءه فقط.

## التوليد (السيرفر/المشغّل)
```bash
# أول مرة فقط: endpoint + مفتاح السيرفر العام — يُخزَّنان في hosts.json
py generate-host.py --host-id almalla-001 \
    --endpoint 203.0.113.10 --server-pubkey "<server-wg-pubkey>"
# أو على ويندوز:  .\generate-host.ps1 -HostId almalla-001 -ServerIP 203.0.113.10 -ServerPubKey "<...>"

# مضيف لاحق:
py generate-host.py --host-id street-002
# إعادة توليد بأسرار جديدة (نفس الـ IPs):
py generate-host.py --host-id almalla-001 --force
```

الناتج في `generated/`:
- `<host>.rsc` — يُسلَّم للمضيف (يحوي سرّه — لا يُرفع لأي مستودع).
- `<host>.server.conf` — بلوك `[Peer]` + `clients.conf` للسيرفر.

`hosts.json` = سجل التخصيص (IPs + مفاتيح عامة + تلميح سرّ فقط) —
مشترك بين مولّدَي Python وPowerShell.

## متطلبات الراوتر
RouterOS v7+ بحزمة `wireless` (الأجهزة بحزمة `wifi` الجديدة تُسجَّل
كتحذير وتُضبط يدوياً). يُسلَّم للمضيف مع `HOST-GUIDE.md`.
