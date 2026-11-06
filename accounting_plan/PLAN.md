# سايبر WiFi — نظام محاسبة الشبكة الكامل + استكمال المايكروتيك
## وثيقة التنفيذ المرجعية (Accounting & MikroTik Completion)

> **الحالة:** قيد التنفيذ — ACC-00 + ACC-01 + ACC-02 + ACC-03 + ACC-04 + ACC-05 + ACC-07 + ACC-08 + ACC-10 + ACC-11 + ACC-12 منجزة (الملفات المشتركة مُجمَّدة)
> **أُنشئت:** 2026-10-26 · **النطاق:** `testapp` (بيئة التطوير المعزولة — يُمنع المساس بالإنتاج)
> **الأساس:** تحليل 117 لقطة لتطبيق «محاسب شبكتي» (com.alqimma / cardnet1.com v1.0.85) + اختبار حي ADB لأربعة تطبيقات (محاسب شبكتي، MikroNet hordev، ديرها m-tech، شبكات shabakat.app v4.0.3) + بحث منافسي اليمن + تحليل ميكرونت السابق (175 لقطة)
> **الرموز:** ⬜ لم تبدأ | 🔶 قيد التنفيذ | ✅ منجزة | ⏸️ مؤجلة | 🧪 بانتظار اختبار

---

## 0) عقد العزل والتوازي (إلزامي — قبل أي سطر كود)

### 0.1 مالكو المسارات

| المسار | يُنفَّذ في | نطاق الملفات المملوك |
|---|---|---|
| **Track MK** — استكمال المايكروتيك | المحادثة المنفصلة الحالية | `network_owner_app/lib/features/mikrotik/**` · جداول `mikrotik_*` · مسارات `/network-owner/mikrotik/*` · `tools/routeros_sim.py` |
| **Track ACC** — نظام المحاسبة | سبرنتات هذه الوثيقة | `network_owner_app/lib/features/accounting/**` · جداول `acc_*` فقط · `routes/api_accounting.php` · `app/Http/Controllers/Api/Accounting/**` · `app/Filament/Resources/Accounting/**` |

### 0.2 الملفات المشتركة — تُلمس مرة واحدة في Sprint A0 ثم تُجمَّد

| الملف | الإضافة المسموحة (سطر/كتلة إضافية فقط) |
|---|---|
| `bootstrap/providers.php` | `App\Providers\AccountingServiceProvider::class` — يسجّل `routes/api_accounting.php` |
| `feature_keys.dart` | كتلة مفاتيح `acc.*` ملحقة دفعة واحدة |
| `router.dart` | مسارات `/accounting/*` ملحقة دفعة واحدة |
| `pubspec.yaml` | اعتماديات المحاسبة تُضاف دفعة واحدة (تُدقَّق في vendor-audit أولاً) |
| الشاشة الرئيسية/القائمة | بطاقة/مدخل «المحاسبة» واحد خلف `FeatureGate('acc.module')` |

بعد A0: أي تعديل على ملف مشترك يحتاج تنسيقاً بين المسارين (رسالة `question` عبر بروتوكول الوكلاء).

### 0.3 قواعد ذهبية (لا استثناءات)

1. كل migration **additive فقط** — جداول/أعمدة جديدة، لا تعديل/حذف للموجود.
2. جداول المحاسبة كلها بادئة `acc_` ومربوطة بـ `network_owner_id` (عزل المستأجر).
3. خدمة الترحيل `AccPostingService` **تقرأ** `transactions`/`cards`/`wallet_logs` فقط — ممنوع update/delete/insert عليها.
4. لا تعديل على: auth, wallets, payout_requests, commission_settings, advances, topup, referral, orders العميل.
5. كل شاشة محاسبة خلف `FeatureGate` — `enforce=0` أثناء التطوير (allow-all).
6. كل سبرنت: تحليل `flutter analyze` نظيف + اختبارات وحدة + ADB live على الجهاز.
7. الـ staging منفصل تماماً؛ الإنتاج لا يُلمس إلا بدورة النشر المعتمدة.
8. الخط: Cairo — الهوية: أبيض/كحلي/أحمر — RTL أصيل — Material 3.

---

## 1) نموذج الأدوار الثلاثة (محاسب شبكتي مُضاهى)

المالك (network_owner) ينشئ **حسابات تشغيل فرعية** داخل نظامه:

| الدور | يعمل على | الصلاحيات |
|---|---|---|
| **إدارة (acc_admin)** | تطبيق المالك — قسم المحاسبة كاملاً | كل الأقسام + إعدادات + اعتمادات |
| **موزع (acc_distributor)** | تطبيق المالك — واجهة موزع (أو تطبيق مخصص لاحقاً) | البيع لنقاط البيع، التحصيل، طلبات POS، تقريره |
| **نقطة بيع (acc_pos)** | واجهة POS مبسّطة | طلب حزم كروت بالنقاط، أرصدة، سحب ربح، تحصيلاته |

- جدول `acc_agents`: (id, network_owner_id, user_id FK users [حساب تطبيق موجود], role[admin|distributor|pos], display_name, phone, daily_limit_per_category JSON, cash_allowed, credit_allowed, status, commission_mode, commission_value)
- دخول الموظف: نفس تطبيق المالك — `role` من `acc_agents` يوجّهه للواجهة الصحيحة (لا جداول auth جديدة).

---

## 2) نموذج البيانات المحاسبي (`acc_*` — كلها additive)

### 2.1 المخزون والكروت
- `acc_card_categories`: (name, sell_price, cost_price, sort_order, is_active, unit_label, source_binding[platform|mikrotik|any])
- `acc_stock`: (category_id, qty, avg_cost) — رصيد المخزون لكل فئة
- `acc_stock_movements`: (category_id, type[in|out|adjust|sale|return|damaged|order_fill], qty, unit_cost, ref_type, ref_id, agent_id, note, created_at) — **لا تُحذف أبداً**
- `acc_card_batches`: كروت مولّدة/مستوردة (source, router_id?, template_id?, codes JSON أو ربط بجدول cards)
- `acc_suppliers`: (name, phone, note)
- `acc_purchases`: (supplier_id, invoice_no, category_id, qty, unit_price, currency, exchange_rate, total, date, note)
- `acc_returns`: (kind[purchase_return|sale_return|card_return], ref_id, qty, amount, reason, date)
- `acc_damaged`: (category_id, qty, reason, evidence_note, date)
- استيراد الكروت: ملف Excel/CSV → `acc_card_imports` (filename, rows_count, status, errors JSON)

### 2.2 نقاط البيع والطلبات
- `acc_pos_points`: نقطة بيع (name, location, owner_name, phone, agent_id, status, credit_limit, points_balance, profit_balance)
- `acc_pos_devices`: جهاز مرتبط بنقطة بيع (device_name, model, agent_user_id, bound_at)
- `acc_pos_orders`: (order_no `PO-YYYYMMDD-NNNNNN`, pos_id, distributor_id?, status[pending|approved|rejected], total_amount, points_total, approved_by, approved_at, note)
- `acc_pos_order_items`: (order_id, category_id, qty, unit_price)
- `acc_points_ledger`: حركة نقاط نقطة البيع (pos_id, delta, reason[order_purchase|conversion|adjustment|bonus], ref_id)
- `acc_profit_ledger`: حركة رصيد أرباح نقطة البيع/الموزع (agent_id|pos_id, delta, reason[sale_commission|withdrawal|adjustment], ref_id)
- `acc_withdrawals`: طلبات سحب رصيد ربح (requester_type[pos|distributor], requester_id, amount, status[pending|approved|paid|rejected], receipt fields, reviewed_by/at)
- `acc_card_exchanges`: استبدال كروت بالنقاط (pos_id, category_id, qty, points_spent, status)

### 2.3 الدورة المستندية (الترحيل — القلب المحاسبي)

**المبدأ:** كل حدث مالي → قيد يومية ثنائي في `acc_journal_entries` + `acc_journal_lines`. القيد لا يُعدَّل ولا يُحذف — الخطأ يُصحَّح بقيد عكسي (reversal).

- `acc_journal_entries`: (entry_no `JE-YYYYMMDD-NNNNN`, doc_type[sale|pos_sale|collection|expense|purchase|return|damaged|withdrawal|adjustment|transfer|card_purchase_platform], doc_ref_id, agent_id, date, currency, exchange_rate, memo, is_posted, posted_at)
- `acc_journal_lines`: (entry_id, account_code, party_type[owner|pos|distributor|customer|supplier|box], party_id, debit, credit)
- `acc_accounts`: دليل حسابات مبسّط (code, name, type[asset|liability|equity|revenue|expense], parent_code) — يُزرع افتراضياً: صندوق رئيسي، مخزون كروت، ذمم نقاط بيع، ذمم موزعين، إيراد مبيعات، عمولات، مصروفات، أرباح نقاط، أرصدة عملاء
- `acc_cash_boxes`: صناديق مالية (name, balance, is_default)
- `acc_cash_transfers`: تحويلات بين الصناديق
- `acc_collections`: التحصيل النقدي (collector_agent_id, party_type[pos|person|customer], party_name, phone, amount, currency, exchange_rate, collected_at, note)
- `acc_debts`/`acc_debt_payments`: مديونيات (party_type, party_id, amount_due, amount_paid, status) + سداد مباشر
- `acc_expenses`: (category, amount, currency, exchange_rate, incurred_at, note, agent_id) + `acc_expense_categories`
- `acc_balances`: رصيد مجمّع لكل طرف (party_type, party_id, balance, updated_at) — يُحدَّث ذرّياً مع القيد

### 2.4 الخصومات والعمولات
- `acc_discount_tiers`: (mode[commission|points|profit_balance|direct_percent], basis[qty|amount], min, max NULL=مفتوح, reward_value, reward_unit[percent|fixed], sort_order, is_active) — تُدار من لوحة Filament أيضاً
- `acc_commissions`: عمولات موزعين (distributor_id, period, sales_amount, commission_amount, status[accrued|paid])

### 2.5 التكامل والتشغيل
- `acc_posting_map`: ربط مصادر المنصة → الحسابات (مثلاً cards سعر البيع → إيراد مبيعات) — JSON إعداد
- `acc_sync_queue`: طابور offline (op_type, payload JSON, status[pending|sent|needs_review], created_at, sent_at)
- `acc_audit_log`: سجل تتبع (agent_id, action, entity, entity_id, meta JSON[latency_ms, payload_hash], created_at) — يغذّي تقرير الأداء كمحاسب شبكتي
- `acc_backups`: ملفات نسخ احتياطي (filename, size, tables_count, checksum, created_by)
- `acc_webhook_events`: قوالب إشعارات الأحداث (event[sale.created|sale.updated|sale.deleted|collection.created|debt.due], channel[whatsapp], template_body, is_active)
- `acc_doc_header`: تخصيص رأس المستند المطبوع (شعار/اسم/نصوص)

### 2.6 الفئات الوسيطة مع الجداول القائمة
- `cards.source` موجود (`platform|mikrotik`) — المحاسبة تضيف مصدراً ثالثاً مفاهيمياً عبر `acc_stock.source_binding` دون تعديل جدول cards.
- بيع الكرت من تطبيق العميل: `transactions` الموجودة ← `acc_posting` يقرأها دورياً/عند الحدث ويُنشئ قيد `card_purchase_platform` + حركة مخزون out.

---

## 3) الدورة المستندية — مواصفة الترحيل (صفر أخطاء)

```
حدث (بيع عميل / طلب POS / تحصيل / مصروف / شراء / مرتجع / تالف / سحب)
        │
        ▼
AccPostingService::post(docType, payload)
        │
        ├─ DB::transaction():  ← معاملة ذرّية واحدة
        │    1) acc_journal_entries (+lines مدين/دائن متوازنة)
        │    2) acc_stock_movements (إن لزم) + تحديث acc_stock
        │    3) acc_points_ledger / acc_profit_ledger (إن لزم)
        │    4) acc_balances (تحديث رصيد الطرف)
        │    5) acc_audit_log
        │
        └─ أي فشل → rollback كامل + op في acc_sync_queue(status=needs_review)
```

**قواعد التوازن:** Σdebit = Σcredit لكل قيد — مرفوض آليّاً غير المتوازن. `idempotency_key` على كل مستند يمنع الترحيل المكرر. إعادة تشغيل آمنة (replayable) للطابور.

---

## 4) الـ API (`/api/network-owner/accounting/*` — routes/api_accounting.php)

```
# إدارة (acc_admin)
GET    /summary                      ملخص تنفيذي (مبيعات/تحصيلات/مصروفات/مخزون/نتيجة تشغيلية)
GET    /dashboard/trend?days=30      اتجاه المبيعات
CRUD   /categories                   فئات الكروت/الباقات
GET    /stock · POST /stock/adjust   المخزون + حركاته
CRUD   /agents                       حسابات موزع/نقطة بيع/إدارة
CRUD   /pos                          نقاط البيع + أجهزتها
GET    /pos-orders · POST /pos-orders/{id}/approve|reject
CRUD   /suppliers · /purchases · /returns · /damaged · /expenses
GET    /collections · POST /collections        التحصيلات
GET    /debts · POST /debts/{id}/pay           المديونيات والسداد
CRUD   /cash-boxes · POST /cash-boxes/transfer الصناديق والتحويلات
GET    /balances?party=...           أرصدة الأطراف
GET    /journal · GET /journal/{id}  القيود
CRUD   /discount-tiers               شرائح الخصم (تنعكس في Filament أيضاً)
GET    /reports/sales|pos-performance|distributor-commissions|collections-daily
GET    /audit-log                    سجل التتبع
GET    /currencies                   من ExchangeRateSetting الموجود (قراءة)
POST   /backup · GET /backups        نسخ احتياطي
GET    /sync/pending · POST /sync/push   مركز المزامنة

# موزع (acc_distributor)
GET    /dist/home                    فئات + متبقٍّ يومي + أرصدة POS
POST   /dist/sale                    بيع نقد/آجل لنقطة بيع
GET    /dist/pos-orders · POST .../approve|reject
POST   /dist/collections · GET /dist/debts · POST /dist/debts/{id}/pay
GET    /dist/report · /dist/commissions

# نقطة بيع (acc_pos)
GET    /pos/home                     رصيد نقاط + رصيد أرباح + حزم
POST   /pos/orders                   إرسال طلب حزم
GET    /pos/orders · /pos/collections-received
POST   /pos/withdrawals · GET /pos/withdrawals
POST   /pos/exchange-cards           استبدال كروت بالنقاط

# الاشتراك (نفس نمط mikrotik)
GET    /billing/plans · /billing/entitlements · POST /billing/subscribe · GET/POST /billing/payments
```

الأمان: `auth:sanctum` + `can:network_owner` + سياسة `acc:{permission}` من دور `acc_agents` — كل موجّه يتحقق.

---

## 5) شاشات تطبيق المالك (`features/accounting/`)

```
features/accounting/
├── data/            acc_api_service, posting_cache, models
├── presentation/
│   ├── screens/
│   │   ├── acc_home_screen.dart            الملخص التنفيذي + اتجاه 30 يوم + بطاقات
│   │   ├── inventory_screen.dart           الأصناف/الأرصدة/حركات
│   │   ├── card_categories_screen.dart     الفئات والأسعار
│   │   ├── sales_screen.dart               سجل المبيعات + فلاتر
│   │   ├── pos_management_screen.dart      نقاط البيع + الأجهزة
│   │   ├── pos_orders_screen.dart          اعتماد/رفض الطلبات
│   │   ├── agents_screen.dart              المستخدمون والصلاحيات
│   │   ├── network_devices_screen.dart     أجهزة الشبكة (سجل + عدادات)
│   │   ├── collections_screen.dart         تحصيل نقدي + كشف اليوم (PDF)
│   │   ├── debts_screen.dart               سداد الديون/المديونيات
│   │   ├── balances_screen.dart            أرصدة العملاء/الموزعين + سحب
│   │   ├── expenses_screen.dart            المصروفات اليومية
│   │   ├── purchases_screen.dart           المشتريات والموردون
│   │   ├── returns_screen.dart             المرتجع
│   │   ├── damaged_screen.dart             التالف/الفاقد
│   │   ├── discount_tiers_screen.dart      شرائح الخصم
│   │   ├── cash_boxes_screen.dart          الصناديق والتحويلات
│   │   ├── journal_screen.dart             القيود اليومية
│   │   ├── reports_screen.dart             التقارير والمتابعة
│   │   ├── pos_analysis_screen.dart        تحليل قوة نقاط البيع
│   │   ├── audit_log_screen.dart           سجل التتبع
│   │   ├── sync_center_screen.dart         مركز المزامنة
│   │   ├── backup_screen.dart              النسخ الاحتياطي
│   │   ├── acc_settings_screen.dart        سياسة الجلسة/الجلسات/المظهر
│   │   ├── acc_subscription_screen.dart    باقات المحاسبة + الدفع
│   │   ├── dist_home_screen.dart           واجهة الموزع (بيع + متبقٍّ يومي)
│   │   ├── dist_orders_screen.dart · dist_collections_screen.dart
│   │   ├── dist_report_screen.dart · dist_commissions_screen.dart
│   │   ├── pos_home_screen.dart            نقطة بيع (نقاط/أرباح/حزم)
│   │   ├── pos_orders_screen.dart · pos_withdrawals_screen.dart
│   │   └── pos_exchange_screen.dart
│   └── widgets/      AccStatCard, AccListItem, PartyPicker, AmountField(currency),
│                     JournalEntryCard, EmptyState, PeriodFilter …
└── providers/        acc_providers (Riverpod)
```

**مبدأ البناء:** معمارية specs تعريفية كما Sprint 5 — شاشة قائمة/نموذج عامّة تُغذّى بتعريفات أقسام → تسريع هائل واتساق كامل.

---

## 6) نظام الاشتراك والتحكم من لوحة المشرف (Filament)

### 6.1 جداول (موازية لـ mikrotik_* — نفس النمط المُثبَت)
- `acc_plans`: (name, description, price, currency, duration_days, features JSON, is_active, sort_order)
- `acc_subscriptions`: (network_owner_id, plan_id NULL=تجربة, status[trial|active|expired|cancelled], starts_at, ends_at, payment_request_id)
- `acc_payment_requests`: (network_owner_id, plan_id, amount, sender_name, bank_account_id, transfer_receipt_number, receipt_image, status, admin_note, reviewed_by/at)

### 6.2 إعدادات `app_settings` (بدون تحديث تطبيق)
- `acc.trial_days` (افتراضي 30 — قابلة للتعديل: أسبوع/شهر/3 أشهر/6/سنة…)
- `acc.enforce` (0=سماح كامل أثناء الإطلاق / 1=فرض الباقات)
- `acc.free_features` (JSON — ميزات مجانية دائماً)
- `acc.pricing_note`، `acc.trial_is_paid` (تجربة مجانية أو مدفوعة رمزياً)

### 6.3 لوحة Filament (مجموعة «المحاسبة»)
- موارد: AccPlanResource · AccSubscriptionResource · AccPaymentRequestResource (موافقة ذرّية تنشئ اشتراكاً / رفض بسبب) · AccDiscountTierResource · AccAgentResource · AccJournalEntryResource (قراءة) · AccReportResource (ملخصات)
- الإعدادات تُحرَّر من مورد AppSettings الموجود.

### 6.4 الدفع (مساران — نفس مايكروتيك)
خصم محفظة المالك (lockForUpdate + WalletLog debit reference_type=`acc_subscription`) **أو** طلب تحويل بإيصال (اسم مودع + رقم سند + صورة + إشعار أدمن).

### 6.5 نظام محاسبة لوحة المشرف (اختياري — مرحلة لاحقة)
Views قراءة-فقط فوق الموجود: إيرادات اشتراكات (mikrotik+acc)، عمولات مبيعات محصّلة، payouts مدفوعة/معلقة، مصروفات منصة، صافي دخل بفترة + تصدير CSV. **بلا جداول مالية جديدة ولا مساس بالمحفظة.**

---

## 7) استكمال مهام المايكروتيك (Track MK — تُنفَّذ في المحادثة الأخرى)

| # | المهمة | الهدف |
|---|---|---|
| M1 ⬜ | توليد كروت User Manager v6 + v7 منفصلين | مضاهاة شبكات |
| M2 ⬜ | أرشيف دفعات طباعة + إعادة طباعة | شبكات/hordev |
| M3 ⬜ | تحويل مضيف (Host/DHCP Lease) إلى عميل مسجّل | شبكات |
| M4 ⬜ | تشخيص موجّه بالأدلة (رفض دخول/صلاحية/رصيد/بروفايل) | شبكات |
| M5 🔶 | الوصول عن بُعد: محلي/SSL+DDNS/رياي VPN + كشف المتاح | ROADMAP §10 |
| M6 ⬜ | فوترة دورية + قطع/إعادة تلقائية (scheduler على الراوتر) | hordev/M-Tech |
| M7 ⬜ | محرك إشعارات واتساب بقوالب أحداث | hordev/محاسب |
| M8 ⬜ | سجل أبراج/معدات/فريق عمل | hordev/M-Tech |
| M9 ⬜ | قفل PIN لقسم الراوتر | ديرها |
| M10 ⬜ | نوع استخدام الشبكة (توزيع/دمج/مدمج) يوجّه الأدوات | شبكات |
| M11 ⬜ | استكمال: Ping هاتف/راوتر + DNS + ساعة الراوتر/NTP | شبكات |
| M12 ⬜ | خريطة أجهزة/نقاط وصول مرئية | شبكات |
| M13 ⬜ | تبديل الراوتر النشط + تفضيلات اتصال لكل راوتر | شبكات |
| M14 ⬜ | طباعة حرارية ESC/POS مباشرة | معلّقة في ROADMAP |
| M15 ⬜ | FTP لملفات الراوتر (backup/قوالب ZIP) | معلّقة في ROADMAP |

> كلها داخل `features/mikrotik/**` — صفر تداخل مع مسار المحاسبة.

---

## 8) خطة السبرنتات المتوازية (Track ACC)

```
A0 ✅ التأسيس المعزول (نُفِّذ 2026-10-26 — مُجمَّد)
     providers.php + api_accounting.php فارغة + feature_keys acc.* +
     مسار /accounting + بطاقة دخول خلف FeatureGate + acc_service_provider
A1 ✅ النواة المحاسبية: acc_accounts + acc_journal_* + AccPostingService
     + acc_balances + acc_audit_log + idempotency + اختبارات توازن القيود (12 ✅)
A2 ⬜ المخزون: acc_card_categories/stock/movements + شاشتا المخزون والفئات
A3 ⬜ الأطراف: acc_agents + acc_pos_points/devices + شاشتا المستخدمون ونقاط البيع
A4 ⬜ طلبات POS: orders/items + واجهتا طلب (POS) واعتماد (إدارة/موزع) + ترحيل ذرّي
A5 ✅ الحركة المالية: collections + debts(+payments) + cash_boxes/transfers + expenses(+categories)
     + قيود تلقائية لكل حدث + تعدد عملات read-only — نُفِّذ 2026-10-27
     (purchases/returns/damaged انتقلت لنطاق ACC-02)
A6 ⬜ واجهة الموزع كاملة (بيع نقد/آجل + متبقٍّ يومي + تحصيل + عمولات)
A7 ✅ واجهة نقطة البيع كاملة (نقاط/أرباح/حزم/سحب/استبدال)
     — نُفِّذ 2026-10-30: acc_withdrawals + acc_card_exchanges +
     PosHome مجمَّع (نقاط+أرباح+حزم+نشاطات) + سحوبات بحجز/استرداد
     + استبدال نقاط↔مخزون+قيد + إصلاح بوابة دخول الوكلاء + ADB live
A8 ✅ ترحيل منصة سايبر: خدمة تقرأ transactions بطاقة البيع → قيد+مخزون (قراءة فقط)
     — نُفِّذ 2026-10-29: acc_posting_map + حارس كتابة مفروض + قيد
     card_purchase_platform متوازن + حركة مخزون لكل كرت + idempotency
A9 ✅ التقارير: الملخص التنفيذي + كشف تحصيلات PDF + اتجاه 30يوم + تحليل POS + سجل تتبع
     — نُفِّذ 2026-10-29: AccReportsService يُجمِّع أرجل القيود نفسها (تطابق
     القيود بالبنية) + journal browser + audit log + كشف تحصيل PDF بالقاهرة RTL
A10 ✅ شرائح الخصم + سحب أرصدة + طلبات سحب الربح + webhook/واتساب قوالب
A11 ✅ اشتراكات المحاسبة (طرف التطبيق): acc_plans/subscriptions/payment_requests
     + API billing + شاشة الباقات + AccFeatureGate/Paywall + دفع محفظة/إيصال
     — نُفِّذ 2026-10-29 بنمط mikrotik؛ enforce=0 مزروعاً؛ Filament تبقى ADM-01
A12 ✅ مركز مزامنة offline + نسخ احتياطي/استعادة + تخصيص رأس المستند
     — نُفِّذ 2026-10-29: acc_sync_queue (pending/sent/needs_review
     بمفتاح client_op_id للإعادة المجانية) + /sync/push يعيد تشغيل
     العمليات عبر خدماتها نفسها + acc_backups تصدير/استيراد/استعادة
     ذرّية بالتحقق من البصمة + acc_doc_header + 3 شاشات
A13 ⬜ تلميع UX/UI نهائي + أداء + اختبارات شاملة + إطلاق staging

Track MK (موازٍ — المحادثة الأخرى): M1..M15 حسب أولوية ROADMAP §10
اختياري لاحقاً: محاسبة لوحة المشرف (§6.5)
```

**قابلية التوازي داخل ACC:** A2/A3 مستقلان؛ A4 يحتاج A2+A3؛ A5 يحتاج A1؛ A6/A7 يحتاجان A4؛ A8 يحتاج A1 فقط ويمكن باكراً؛ A9 بعد A5؛ A11 مستقل تماماً (يمكن تقديمه)؛ A10/A12 مستقلان.

---

## 9) معايير التنفيذ (عقد الجودة)

- **Clean Code:** نمط `features/{acc}/data+presentation+providers`؛ خدمات رفيعة أحادية المسؤولية؛ نماذج serialization مختبرة؛ صفر تكرار (widgets مشتركة + section specs)
- **Flutter:** `flutter analyze` نظيف · اختبارات وحدة لكل خدمة ترحيل/مزامنة · ADB live لكل سبرنت
- **Backend:** `php -l` + Feature tests للـ endpoints الحرجة (ترحيل/اعتماد/اشتراك) · معاملات DB ذرّية · idempotency إجباري
- **UX/UI عالمي:** Material 3، Cairo، هوية سايبر، RTL كامل، أيقونات رسومية متسقة (لا إيموجي)، حالات skeleton/empty/error موحّدة (`ui_states.dart`)، dark mode، bottom-sheet forms، مسارات موجّهة بالمهمة (كما شبكات)، حجم خط لا يقل عن معايير الوصول، أرقام عربية واضحة في المبالغ
- **الأمان:** سياسات لكل endpoint · كلمات مرور الراوتر/القنوات مشفّرة · لا أسرار في الكود · audit لكل عملية مالية
- **النسخة التجريبية:** تُعبَّأ ببيانات واقعية (seeder) — لا تجربة باردة كمحاسب شبكتي
- **الأداء:** فهارس على (network_owner_id, party, date, status) · pagination لكل القوائم · تحميل كسول

---

## 10) معايير القبول (Definition of Done)

- [ ] كل شاشات الأقسام الأربعة تعمل على staging بثلاثة أدوار حقيقية
- [ ] بيع كرت من تطبيق العميل يظهر قيداً ومخزوناً في المحاسبة خلال ثوانٍ — صفر تكرار
- [ ] طلب POS كامل: طلب→اعتماد→نقاط→ربح→قيد — في معاملة واحدة
- [ ] enforce=1 يقفل المحاسبة خلف الباقة، وتغيير trial_days من لوحة Filament ينعكس فوراً
- [ ] مزامنة offline: بيع بلا شبكة → طابور → ترحيل صحيح عند الاتصال
- [ ] صفر تعديل/تعطيل لأي تدفق قائم (محفظة/كروت/سحب/عمولات)
- [ ] تحليل نظيف + اختبارات خضراء + ADB live موثّق بلقطات

## سجل الإنجاز

| التاريخ | المهمة | الحالة |
|---|---|---|
| 2026-10-26 | تحليل محاسب شبكتي (117 لقطة + ADB ثلاثي الأدوار) + منافسين (شبكات/MikroNet/ديرها/ميكرونت) + سوق اليمن + توافق السورس + اعتماد الوثيقة | ✅ |
| 2026-10-26 | ACC-00 التأسيس المعزول: `AccountingServiceProvider` + `providers.php` (سطر) + `routes/api_accounting.php` فارغة + `AccFeatures` (28 مفتاح `acc.*`) + مسار `/accounting` + بطاقة «المحاسبة» خلف `FeatureGate` + `AccHomeScreen` placeholder — analyze نظيف، صفر تغيير سلوكي | ✅ |
| 2026-10-26 | ACC-01 النواة المحاسبية: 5 migrations (acc_accounts/entries/lines/balances/audit_log) + 5 موديلات + `AccPostingService` (ترحيل ذرّي، توازن إجباري، idempotency، قيد عكسي، أرصدة أطراف، audit بـ latency+hash، خطاف needs_review جاهز لـ ACC-12) — 12 اختباراً / 43 تأكيداً خضراء | ✅ |
| 2026-10-27 | ACC-03 الأدوار الثلاثة: 3 migrations (acc_agents/pos_points/pos_devices) + 3 موديلات + `AccContext` (حلّ المستأجر: مالك أو وكيل active — بلا جداول auth) + `EnsureAccountingContext`/`AuthorizeAccPermission` (سياسات `acc:*` بالمصفوفة) + مسارات `/me`, CRUD `/agents`, `/pos`+devices + شاشتا «المستخدمون» و«نقاط البيع» + `acc_home` موجّهة بالدور — 13 اختباراً/62 تأكيداً خضراء (دخول الأدوار الثلاثة، عزل المستأجر، فريد UID للجهاز) + analyze نظيف | ✅ |
| 2026-10-27 | ACC-04 طلبات نقاط البيع: 4 migrations (acc_pos_orders/items + points_ledger + profit_ledger) + 4 موديلات + `AccPosOrderService` (إنشاء بـ order_no+idempotency؛ اعتماد ذرّي واحد: خصم مخزون order_fill + خصم نقاط + عمولة موزع للربح + قيد pos_sale متوازن عبر AccPostingService + audit؛ رفض بدون أثر مالي) + `AccPosOrdersController` (مسارات `/pos-orders`+approve/reject + `/dist/pos-orders` + `/pos/orders` لسطح POS) + شاشتا الاعتماد والطلب + ربط acc_home بالأدوار — 12 اختباراً/99 تأكيداً (دورة كاملة، replay، rollback عند نقص النقاط/المخزون، عزل مستأجر) + analyze نظيف. ملاحظة: خطاف المخزون `Schema::hasTable` يُفعَّل عند هبوط ACC-02 — صفر تعارض | ✅ |
| 2026-10-27 | ACC-02 المخزون وفئات الكروت: 8 migrations (card_categories/stock/movements/suppliers/purchases/returns/damaged/card_imports — أرشميتها 03xxxx بين ACC-03 وACC-04) + 8 موديلات + `AccStockService` (حركة موقّعة واحدة + رصيد مقفل lockForUpdate في معاملة ذرّية، متوسط تكلفة مرجّح يُعاد حسابه عند كل إدخال، `adjust` تسوية مطلقة بدلتا موقّعة، رفض السالب بـ 409) + مشتريات (in + قيد purchase نقد/آجل بذمة مورد) وتالف (damaged + مصروف←مخزون) ومرتجع (اتجاه حسب kind + قيود return متوازنة) + `syncRouterCards` — كروت `source=mikrotik` تدخل المخزون تلقائياً: قراءة-فقط على cards/card_categories/networks، حركة in لكل كرت + sale/out للمُباع/المنتهي، فئة acc تُنشأ تلقائياً مرتبطة بـ card_category_id (أو مطابقة اسم+سعر)، idempotent بفهرس (ref_type=card, ref_id, type) فريد + سجل في acc_card_imports — يعمل كسولاً على كل قراءة `/stock` + POST `/stock/sync` + استيراد CSV برأس/بدون رأس بأخطاء لكل سطر + 6 controllers + 20 مساراً بصلاحيات categories/stock/suppliers/purchases/returns/damaged.* + شاشتا «فئات الكروت» (CRUD + تعطيل/حذف محمي بالحركات) و«المخزون» (إجمالي+قيمة، أرصدة بتحذير انخفاض، سجل حركات غير قابل للحذف، تسوية جرد، زر مزامنة) + ربط acc_home خلف AccFeatures — 13 اختباراً/89 تأكيداً خضراء (CRUD، متوسط مرجّح، ذرّية، ترحيل تلقائي، idempotent، فئة مربوطة، CSV، عزل مستأجر) + analyze نظيف + ADB live على Redmi Note 8 Pro (قسم المحاسبة يعمل — 404 /me متوقع قبل نشر staging) — خطاف ACC-04 `applyStockOut` فُعِّل بلا تعديل — صفر تعارض | ✅ |
| 2026-10-29 | ACC-08 ترحيل مبيعات تطبيق العميل: migration `acc_posting_map` + `AccPostingMap` (ربط مصدر→حسابات JSON overlay على الافتراضيات) + `AccPlatformReadOnly` (المنع أمنياً في الكود: أي كتابة/DDL على transactions/transaction_cards/cards/card_categories/wallet_logs/networks/users/wallets أثناء التزامن يرمي AccPlatformException داخل معاملة البيع فيردّها) + `AccPlatformSalesService` — مسح `transactions` المكتملة غير السلفية → قيد `card_purchase_platform` (Dr صافي+عمولة ← Cr إيراد + COGS) بعملة الشبكة وسعرها والترحيل بالأساس شمال + حركة `in`+`sale` لكل كرت بمرجع (card,id) المطابق لتوقيع مزامنة الراوتر (صفر ازدواج بالاتجاهين) والفائض بمرجع platform_transaction + idempotency `platform-sale-{tx}` وفهرس الحركات الفريد + 4 مسارات platform.* (`/platform-sales` كسول + `/platform-sales/sync` + `/posting-map`) — 11 اختباراً/73 تأكيداً خضراء؛ صفر مساس بالتدفقات القائمة | ✅ |
| 2026-10-27 | ACC-05 الحركة المالية: 7 migrations (acc_cash_boxes/transfers + acc_collections + acc_debts/debt_payments + acc_expense_categories/expenses) + 7 موديلات + `AccMoneyService` (تحصيل Dr صندوق/Cr ذمة · دين افتتاحي adjustment · سداد ذرّي payment+collection+قيد+قلب الحالة · تحويل صناديق بقفل الصفين · مصروف Dr مصروفات/Cr صندوق · إلغاء بقيد عكسي · رصيد افتتاحي للصندوق Dr صندوق/Cr حقوق ملكية) + تعدد عملات: ExchangeRateSetting قراءة-فقط والترحيل دائماً بالأساس `north` + 4 controllers + مسارات `/collections /debts(+pay,+payments) /cash-boxes(+transfer,+transfers) /expenses(+categories) /currencies` + أسماء `/dist/*` و`/pos/collections-received` + `money_api.dart` + 4 شاشات (تحصيلات/مديونيات/صناديق/مصروفات) مربوطة بـ acc_home خلف FeatureGate — 16 اختباراً/94 تأكيداً (قيد متوازن، سداد جزئي/كامل، supplier payable، تحويل عابر للعملة، إلغاء بعكس، عزل مستأجر، أدوار dist/pos) + analyze نظيف | ✅ |
| 2026-10-29 | ACC-11 اشتراك المحاسبة (طرف التطبيق): 4 migrations (acc_plans + acc_payment_requests/acc_subscriptions بـ network_owner_id — الاشتراك للمستأجر كاملاً مالكاً ووكلاء + بذر acc.trial_days=30/acc.enforce=0/acc.free_features/acc.pricing_note/acc.trial_is_paid) + 3 موديلات + `AccBillingController` بنمط NetworkOwnerMikrotikSubscriptionController بالضبط (تجربة كسولة بلا إعادة بعد انتهاء تاريخي، entitlements يقلب المنتهي لـ expired ويعيد المفاتيح المجانية، دفع محفظة بـ lockForUpdate + WalletLog debit بـ reference_type=acc_subscription في معاملة ذرّية، طلب تحويل بإيصال — pending واحد لكل مستأجر + إشعار أدمن + user_id للمقدّم) + 5 مسارات `/billing/*` (entitlements مفتوحة لكل أدوار السياق؛ plans/payments/subscribe خلف `billing.*` — موزع/POS يُرفضان 403) + `AccBillingApi` + `AccEntitlementService` + `accEntitlementProvider` (allow-all حتى enforce=1) + `AccFeatureGate`/`AccPremiumLockCard` (Paywall موحد — صفر لمس router.dart) + `AccSubscriptionScreen` (حالة+باقات+محفظة/تحويل+طلبات+pricing_note) + تحويل acc_home وdist_home للبوابة وبلاطة «الاشتراك والباقات» — 12 اختباراً/78 تأكيداً خضراء + analyze نظيف على ملفات المحاسبة؛ Filament يتبع ADM-01 | ✅ |
| 2026-10-29 | ACC-10 شرائح الخصم + الأرصدة/السحوبات + إشعارات واتساب: 3 migrations (`acc_discount_tiers` — أنماط commission/points/profit_balance/direct_percent × أساس qty/amount، قوس [min,max] بنهاية مفتوحة اختيارية + `acc_webhook_events` قوالب {placeholder} + `discount_amount` إضافية additive على acc_sales/acc_pos_orders) + `AccDiscountService` (ترشيح أعمق قوس مطابق: min الأعلى ثم sort_order ثم id — قراءة فقط داخل معاملة المستدعي) + `AccTierRewardWriter` (مكافآت نقاط/أرباح الـ POS داخل نفس المعاملة الذرّية — تتراجع مع المستند) + `AccWebhookService` (render لكل قالب نشط بعد الالتزام + wa.me مع تطبيع الرقم اليمني 967 + دفع داخلي لمستخدم الوكيل المرتبط عبر NotificationService + audit `webhook.dispatch` لكل إرسال — لا يرمي أبداً) + تطبيق الشرائح ذرّياً: `AccDistService::sale` (الخصم على الصافي المدفوع/الذمة/الإيراد والعمولة على الصافي) و`AccPosOrderService::approve` (النقاط المخصومة تُسقَف بالقيمة المخفَّضة وpoints_total تُجمَّد على المصروف الفعلي + discount_amount) + `notifications` في ردود `/dist/sale` و`/pos-orders/{id}/approve` و`/collections` + مسارات `/discount-tiers/*`+match و`/balances?party=` و`/webhook-events/*`+preview و`/notifications/debt-due` (خلف discount-tiers.* / balances.read / webhooks.* للمالك والإدارة) + `loyalty_api.dart` + 3 شاشات (شرائح الخصم CRUD / الأرصدة والسحوبات بلسنتين: أرصدة الأطراف + مراجعة طلبات السحب اعتماد/صرف/رفض / إشعارات واتساب بلسنتين: قوالب+معاينة وتذكير ديون يفتح wa.me) + 3 بلاطات في acc_home — 11 اختباراً/87 تأكيداً خضراء (تطبيق direct_percent على بيع، نقاط/أرباح/عمولة تتراكب، سقف الدفع المسبق بالنقاط، dispatch القوالب + audit، تذكير الديون، أرصدة بأسماء، دورة سحب كاملة) + 60 اختباراً سابقاً بلا انكسار + php -l + analyze نظيف على ملفات ACC-10 | ✅ |
| 2026-10-29 | ACC-12 مركز المزامنة offline + النسخ الاحتياطي: 3 migrations (`acc_sync_queue` — pending/sent/needs_review، فريد (owner, client_op_id) كمفتاح idempotency على مستوى الدفعة + `acc_backups` سجل اللقطات بحجم/جداول/سجلات/sha256 + `acc_doc_header` صف واحد لكل مستأجر بشعار خاص يُقدَّم عبر GET /doc-header/logo) + 3 موديلات + `AccSyncService` — 13 نوع عملية بيضاء (collection/debt/pay/expense/transfer/dist.sale/pos.order/withdrawal/exchange/stock.adjust/purchase/return/damaged) تُعاد عبر الخدمات المالكة نفسها بنفس قواعد التحقق، queued_at يملأ حقل التاريخ الحقيقي، كل عملية في معاملة مستقلة والفاشلة تركن needs_review بلا إيقاف الدفعة + تفعيل خطاف `AccPostingService::queueFailedOp` بإضافة network_owner_id (post:{doc_type} يظهر في المركز ويُعاد) + `AccBackupService` — تصدير كل جداول acc_* للمستأجر مرتّبة أهل←أبناء في JSON موقّع، استعادة ذرّية كاملة بمعاملة واحدة مع تعطيل FKs وفرض network_owner_id للمستأجر المستعيد، رفض الملف العابث بالبصمة قبل لمس أي صف + `AccDocHeaderController` إعدادات + رفع/حذف/بث الشعار خاصاً + مسارات `/sync/pending|queue|push|{op}/retry|discard` و`/backup(s)/...` و`/doc-header*` خلف sync.push (لكل الأدوار)/sync.read|manage وbackup.* وsettings.* + صلاحية sync.push للموزع وPOS في AccContext + فلاتر: `AccOfflineQueue` (صندوق Hive مستقل، isOfflineError يميّز الانقطاع عن ردود 4xx) + `accWriteOrQueue` رُبِط بمسارات الكتابة في money/pos_app/dist/pos_orders/acc_api — فشل الشبكة يحفظ العملية بدل رمي الخطأ + `SyncApi` + `AccSyncEngine` (دفع الدفعة، إزالة المُقْرَّة، flag للمراجعة، منع التزامن المتداخل) + 3 شاشات (مركز المزامنة: اتصال+عدّادات+عمليات جهاز بحذف سحبياً+طابور خادم بإعادة/استبعاد / النسخ الاحتياطي: إنشاء+تنزيل+استيراد+استعادة بتأكيد / رأس المستند: نموذج+معاينة حية+شعار) + 3 بلاطات في acc_home + flush تلقائي عند عودة الاتصال — 12 اختباراً/74 تأكيداً خضراء (offline→push→قيد متوازن، replay بلا ازدواج، needs_review→إعادة/حذف، خطاف الترحيل، POS يرتبط بنقطة، نسخة→تعديل→استعادة ترجع الحالة، عابث يُرفض، تنزيل/استيراد، رأس المستند، عزل مستأجر) + 32 اختباراً سابقاً للأدوار بلا انكسار + 6 اختبارات Flutter للطابور + php -l وanalyze نظيف — صفر تعارض خارج acc_* | ✅ |
| 2026-10-30 | ACC-07 واجهة نقطة البيع كاملة: 2 migrations (`acc_withdrawals` دورة pending→approved→paid|rejected|cancelled بمفتاح idempotency + `acc_card_exchanges` استبدال نقاط بحزم) + 2 موديلات + `AccPosAppService` (home مجمَّع برحلة واحدة: نقطة+أرصدة+حزم بمخزون/تسعير خادمي + إحصاءات + خلاصة دفاتر/طلبات/تحصيلات؛ سحب ربح بحجز الرصيد ذرّياً ثم اعتماد/صرف عبر قيد withdrawal بـ AccPostingService أو رفض يسترد الحجز أو إلغاء POS لطلبه المعلق؛ استبدال ذرّي: خصم نقاط + دفتر conversion + خصم مخزون + حركة sale + قيد متوازن — تراجع كامل عند أي نقص؛ ledger موحّد نقاط+أرباح) + `AccPosAppController` + `AccWithdrawalsController` (مراجعة الإدارة: list/approve/reject/pay بصندوق نقد) + مسارات `/pos/home|ledger|withdrawals(+cancel)|exchanges|exchange-cards|collections-received` + أسماء `/dist/*` للموزع + إدارة `/withdrawals/*` + فلاتر: `pos_app_api.dart` (11 موديل + عميل رفيع) + `pos_app_providers.dart` + 4 شاشات جديدة (PosHome: بطاقة أرصدة+إحصاءات+إجراءات سريعة+حزم بزرّي طلب/استبدل+خلاصة نشاطات / سحب الأرباح: رصيد+طلب+إلغاء بتأكيد / استبدال النقاط: حزم+تكلفة حية+تحقق رصيد/مخزون فوري+سجل / سجل التحصيلات) + توجيه دور POS في acc_home لـ PosHomeScreen + ترقية نموذج طلب الحزم لقائمة كتالوج `category_id` بتسعير خادمي مع بقاء الصنف الحر + إصلاح بوابة الدخول: `AuthController` يمرّر حاملي صف acc_agents نشط (بموافقة المستخدم — سدّ فجوة جعلت أدوار الوكلاء غير قابلة للدخول) — 16 اختباراً/127 تأكيداً خضراء (home، سحب بحجز/idempotency/إلغاء/رفض يسترد/دورة اعتماد-صرف+قيد، استبدال بخصم نقاط+مخزون+قيد/idempotency/تراجع عند نقص، أدوار+عزل مستأجر+أسماء dist) + مجموعة acc كاملة 98 اختباراً بلا انكسار + php -l + analyze نظيف + **ADB live على Redmi Note 8 Pro**: دخول POS فعلي → PosHome بأرصدة حية → استبدال «باقة يوم» من الواجهة (9800→9300) → طلب حزم PO-20261030-000001 → سجل التحصيلات — 19 لقطة موثقة في live_test/acc07_*.png | ✅ |
