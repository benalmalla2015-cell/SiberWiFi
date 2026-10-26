# سايبر WiFi — نظام محاسبة الشبكة الكامل + استكمال المايكروتيك
## وثيقة التنفيذ المرجعية (Accounting & MikroTik Completion)

> **الحالة:** قيد التنفيذ — ACC-00 منجزة (الملفات المشتركة مُجمَّدة)
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
A5 ⬜ الحركة المالية: collections + debts + cash_boxes/transfers + expenses + purchases/returns/damaged
A6 ⬜ واجهة الموزع كاملة (بيع نقد/آجل + متبقٍّ يومي + تحصيل + عمولات)
A7 ⬜ واجهة نقطة البيع كاملة (نقاط/أرباح/حزم/سحب/استبدال)
A8 ⬜ ترحيل منصة سايبر: خدمة تقرأ transactions بطاقة البيع → قيد+مخزون (قراءة فقط)
A9 ⬜ التقارير: الملخص التنفيذي + كشف تحصيلات PDF + اتجاه 30يوم + تحليل POS + سجل تتبع
A10 ⬜ شرائح الخصم + سحب أرصدة + طلبات سحب الربح + webhook/واتساب قوالب
A11 ⬜ اشتراكات المحاسبة: acc_plans/subscriptions/payments + Filament + Paywall + enforce
A12 ⬜ مركز مزامنة offline + نسخ احتياطي/استعادة + تخصيص رأس المستند
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
