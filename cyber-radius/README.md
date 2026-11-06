# cyber-radius — محرك سايبر (Track CYB-01)

حزمة Docker مستقلة تُنشر على VPS: FreeRADIUS 3.2 (EAP-TLS فقط) + CA خاص بسايبر +
إصدار/إبطال شهادات المشتركين + جسر دفاتر auth/acct إلى باكند `testapp`.

## البنية

```
cyber-radius/
├── docker-compose.yml        # freeradius (UDP 1812/1813/3799) + engine
├── .env.example              # CYBER_ENGINE_URL / CYBER_ENGINE_TOKEN / TZ
├── init-ca.sh                # توليد جذر CA + شهادة السيرفر (مرة واحدة، على الـ VPS)
├── raddb/
│   ├── clients.conf          # مضيفو NAS — HOST_PILOT + كتل generate-host.py
│   ├── certs/                # تُملأ بـ init-ca.sh (gitignored — لا تُرفع)
│   ├── mods-enabled/
│   │   ├── eap               # EAP-TLS فقط — لا md5/gtc/peap/ttls/mschapv2
│   │   ├── detail            # دفتر المحاسبة radacct/<nas>/detail-YYYYMMDD
│   │   └── auth_log          # دفتر المصادقة radacct/<nas>/auth-detail-YYYYMMDD
│   └── sites-enabled/
│       ├── default           # auth :1812 + acct :1813 (مختصر لسايبر)
│       └── coa               # مستمع CoA/Disconnect :3799
├── pki/
│   ├── openssl-cyber.cnf     # إعداد CA (سياسة CN=74XXXXXXX، امتدادات server/client)
│   ├── ca/                   # جذر CA الخاص — لا يغادر السيرفر أبداً (gitignored)
│   ├── clients/              # مخرجات الشهادات لكل مشترك (gitignored)
│   └── scripts/
│       ├── issue-cert.sh     # إصدار شهادة مشترك -> .crt + .key + .p12 مشفّر
│       └── revoke-cert.sh    # إبطال عبر CRL + تحديث raddb/certs
├── engine/
│   └── engine.py             # يلاحق الدفاتر ويPOST الأحداث للباكند (stdlib فقط)
└── host-templates/           # قوالب .rsc المعتمة للمضيفين (CYB-02)
```

## التشغيل على الـ VPS

```bash
# 1) جذر CA + شهادة السيرفر + DH + CRL فارغة (مرة واحدة)
./init-ca.sh

# 2) متغيرات البيئة
cp .env.example .env      # املأ CYBER_ENGINE_URL و CYBER_ENGINE_TOKEN

# 3) التشغيل
docker compose up -d
docker compose logs -f freeradius
```

## إصدار شهادة مشترك

```bash
./pki/scripts/issue-cert.sh 741234567
#  -> pki/clients/741234567/741234567.{key,crt,p12}
#  -> كلمة مرور الـ .p12 تُطبع مرة واحدة — تُسلَّم للتطبيق ولا تُخزَّن
./pki/scripts/revoke-cert.sh 741234567   # إبطال + نشر CRL
docker compose restart freeradius         # التقاط الـ CRL فوراً
```

المشترك يُعرَّف بـ `CN = رقم الشريحة`، و`check_cert_cn=yes` يمنع تبادل الشهادات
بين الهويات. منافذ TLS الأدنى 1.2، وتذاكر الاستئناف معطّلة حتى تُفحص الـ CRL
في كل جلسة.

## جسر المحرك (engine/)

يقرأ دفتري `radacct/**/detail-*` (محاسبة) و`auth-detail-*` (مصادقة) ويحوّل
كل سجل إلى حدث JSON يُPOST إلى `CYBER_ENGINE_URL` بترويسة
`Authorization: Bearer $CYBER_ENGINE_TOKEN`. الأنواع:
`auth.accept`, `auth.reject`, `acct.start`, `acct.interim`, `acct.stop`,
`acct.on`, `acct.off`. الإزاحات تُحفظ في volume `engine-state` ولا تتقدم
إلا بعد استجابة 2xx — تسليم مرة واحدة على الأقل بلا فقد.

## إضافة مضيف جديد

```bash
py host-templates/generate-host.py --host-id almalla-001 \
    --endpoint <vps-ip> --server-pubkey "<wg-server-pub>"
# ألصق محتوى generated/<host>.server.conf (كتلة client) في raddb/clients.conf
docker compose restart freeradius
```

## قواعد التشغيل

1. `pki/ca/private/ca.key` **لا يُرفع للمستودع ولا يغادر السيرفر** (`.gitignore`).
2. المنافذ المكشوفة: UDP 1812 (auth) / 1813 (acct) / 3799 (CoA) — والوصول
   للمضيفين عبر WireGuard فقط (سرّ RADIUS فريد لكل مضيف).
3. الخادم لا يخزن أرصدة — كل حدث يمر للباكند عبر `CYBER_ENGINE_URL`.
