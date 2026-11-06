# سجل المهام المرقّم — المحاسبة + المايكروتيك + لوحة المشرف

> **الحالات:** ⬜ لم تبدأ | 🔶 قيد التنفيذ | 🧪 باختبار | ✅ منجزة | ⏸️ مؤجلة
> **آخر تحديث:** 2026-10-29

## ملخص الأقسام

| الكود | القسم | عدد المهام | مكان التنفيذ |
|---|---|---|---|
| **ACC-00 → ACC-13** | المحاسبة — تطبيق أصحاب الشبكات + الباك إند | **14 مهمة** | هذا المجلد / هذه المحادثة |
| **ADM-01 → ADM-04** | لوحة تحكم المشرف (Filament) | **4 مهام** | هذا المجلد / هذه المحادثة |
| **MK-01 → MK-15** | استكمال إدارة المايكروتيك | **15 مهمة** | المحادثة المنفصلة الأخرى |
| | **الإجمالي** | **33 مهمة** | |

---

## القسم ACC — نظام محاسبة الشبكة (14 مهمة)

| الكود | المهمة | النطاق/الجداول | التبعية | معيار القبول | الحالة |
|---|---|---|---|---|---|
| **ACC-00** | التأسيس المعزول | `AccountingServiceProvider` + `routes/api_accounting.php` + مفاتيح `acc.*` + مسار `/accounting` + بطاقة دخول خلف FeatureGate | — | التطبيق يبنى ويعمل دون أي تغيير سلوكي؛ ملفات المشاركة مُجمَّدة | ✅ |
| **ACC-01** | النواة المحاسبية | `acc_accounts`, `acc_journal_entries/lines`, `acc_balances`, `acc_audit_log`, `AccPostingService` + idempotency | ACC-00 | قيد متوازن لكل حدث؛ اختبارات وحدة للتوازن والذرّية | ✅ |
| **ACC-02** | المخزون والفئات | `acc_card_categories`, `acc_stock`, `acc_stock_movements`, `acc_purchases`, `acc_suppliers`, `acc_returns`, `acc_damaged`, `acc_card_imports` + شاشتا المخزون/الفئات | ACC-01 | رصيد/حركات صحيحة؛ كروت الراوتر تدخل تلقائياً | ✅ |
| **ACC-03** | الأطراف: وكلاء ونقاط بيع | `acc_agents`, `acc_pos_points`, `acc_pos_devices` + شاشتا المستخدمون/نقاط البيع | ACC-00 | إنشاء موزع/POS بصلاحيات وحدود ويعمل دخوله | ✅ |
| **ACC-04** | طلبات نقاط البيع | `acc_pos_orders(+items)` + `acc_points_ledger` + `acc_profit_ledger` + واجهتا الطلب والاعتماد/الرفض | ACC-02, ACC-03 | طلب→اعتماد→مخزون+نقاط+قيد في معاملة واحدة | ✅ |
| **ACC-05** | الحركة المالية | `acc_collections`, `acc_debts(+payments)`, `acc_cash_boxes(+transfers)`, `acc_expenses(+categories)` + شاشاتها | ACC-01 | تحصيل/سداد/مصروف/تحويل صندوق يولّد قيداً صحيحاً | ✅ |
| **ACC-06** | واجهة الموزع كاملة | بيع نقد/آجل لـ POS، متبقٍّ يومي، تحصيل، مديونيات، تقرير، عمولات (`acc_commissions`) | ACC-04, ACC-05 | بيع آجل يظهر ديناً وقيداً؛ تقرير الموزع صحيح | ⬜ |
| **ACC-07** | واجهة نقطة البيع كاملة | رصيد نقاط+أرباح، حزم، طلبات، `acc_withdrawals`, `acc_card_exchanges` | ACC-04 | شراء بالنقاط + طلب سحب ربح يعملان | ✅ |
| **ACC-08** | ترحيل بيع تطبيق العميل | `acc_posting_map` + قارئ `transactions` (قراءة فقط) → قيد+مخزون | ACC-01 | شراء كرت بالتطبيق يظهر محاسبياً دون تكرار | ✅ |
| **ACC-09** | التقارير وسجل التتبع | ملخص تنفيذي، كشف تحصيل PDF، اتجاه 30يوم، تحليل قوة POS، شاشة audit | ACC-05 | أرقام التقرير تطابق القيود 100% | ✅ |
| **ACC-10** | الخصومات والسحوبات والواتساب | `acc_discount_tiers`, `acc_webhook_events`, سحب أرصدة، طلبات سحب الربح | ACC-06, ACC-07 | شريحة خصم تُطبَّق تلقائياً؛ إشعار حدث يعمل | ✅ |
| **ACC-11** | اشتراك المحاسبة — طرف التطبيق | `acc_plans/subscriptions/payment_requests` (migrations+API) + شاشة الباقات + Paywall + دفع محفظة/إيصال | ACC-00 | اشتراك بمحفظة يفعّل القسم؛ paywall يقفل عند enforce=1 | ✅ |
| **ACC-12** | المزامنة offline + النسخ الاحتياطي | `acc_sync_queue`, `acc_backups`, `acc_doc_header` + مركز مزامنة + إعدادات القسم | ACC-04 | عملية بلا شبكة تُرحَّل صحيحاً عند الاتصال؛ نسخة تُصدَّر وتُستعاد | ✅ |
| **ACC-13** | التلميع والإطلاق | UX/UI نهائي، أداء/فهارس، اختبارات شاملة، إطلاق staging، سيدر بيانات تجريبية | كل ما سبق | تحليل نظيف + اختبارات خضراء + ADB موثّق + جاهزية النشر | ⬜ |

## القسم ADM — لوحة تحكم المشرف Filament (4 مهام)

| الكود | المهمة | النطاق | التبعية | معيار القبول | الحالة |
|---|---|---|---|---|---|
| **ADM-01** | موارد اشتراكات المحاسبة | `AccPlanResource`, `AccSubscriptionResource`, `AccPaymentRequestResource` + اعتماد/رفع إيصال ينشئ اشتراكاً ذرّياً | ACC-11 (الجداول) | مشرف ينشئ باقة ويعدّل سعرها/مدتها؛ موافقة تحويل تفعّل اشتراكاً | ⬜ |
| **ADM-02** | إعدادات التحكم المركزي | `acc.trial_days`, `acc.enforce`, `acc.free_features`, `acc.pricing_note` + `AccDiscountTierResource` + `AccAgentResource` | ACC-00 | تغيير فترة التجربة/الفرض/الخصومات من اللوحة ينعكس فوراً بالتطبيق | ⬜ |
| **ADM-03** | محاسبة المنصة (قراءة فقط) | تقارير دخل: اشتراكات MK+ACC، عمولات، payouts مدفوعة/معلقة، مصروفات، صافي، فلترة+تصدير — **Views فوق الموجود بلا تعديل** | — | صافي دخل المنصة صحيح بفترة مختارة؛ صفر مساس بجداول المالية | ⬜ |
| **ADM-04** | متابعة العمليات والأعطال | `AccJournalEntryResource` قراءة + `acc_audit_log` + تنبيهات طابور `needs_review` | ACC-01, ACC-09 | مشرف يرى قيود/تدقيق/أعطال الترحيل ويعالجها | ⬜ |

## القسم MK — استكمال إدارة المايكروتيك (15 مهمة — المحادثة الأخرى)

| الكود | المهمة | التجميع المقترح | الحالة |
|---|---|---|---|
| **MK-01** | توليد كروت User Manager v6 + v7 منفصلين | MK-A | ⬜ |
| **MK-02** | أرشيف دفعات طباعة + إعادة طباعة آخر دفعة | MK-A | ⬜ |
| **MK-03** | تحويل مضيف (Host/DHCP Lease) إلى عميل مسجّل | MK-B | ⬜ |
| **MK-04** | تشخيص موجّه بالأدلة قبل الإجراء | MK-B | ⬜ |
| **MK-05** | الوصول عن بُعد: محلي/SSL+DDNS/رياي VPN + كشف المتاح | MK-C | 🔶 (ROADMAP §10) |
| **MK-06** | فوترة دورية + قطع/إعادة تلقائية للمشتركين | MK-D | ⬜ |
| **MK-07** | محرك إشعارات واتساب بقوالب الأحداث | MK-D | ⬜ |
| **MK-08** | سجل أبراج/معدات/فريق عمل | MK-D | ⬜ |
| **MK-09** | قفل PIN لقسم الراوتر | MK-E | ⬜ |
| **MK-10** | نوع استخدام الشبكة (توزيع/دمج/مدمج) | MK-A | ⬜ |
| **MK-11** | Ping هاتف/راوتر + إعداد DNS + ساعة/NTP | MK-C | ⬜ |
| **MK-12** | خريطة أجهزة/نقاط وصول مرئية | MK-C | ⬜ |
| **MK-13** | تبديل الراوتر النشط + تفضيلات اتصال لكل راوتر | MK-B | ⬜ |
| **MK-14** | طباعة حرارية ESC/POS مباشرة | MK-E | ⬜ |
| **MK-15** | FTP لملفات الراوتر (backup/قوالب ZIP) | MK-E | ⬜ |

---

## مصفوفة التنفيذ المتوازي

```
ACC-00 (بوابة إلزامية — أولاً ووحده)
   ├─→ ACC-01 ──→ ACC-02 ─┐
   │        └──→ ACC-05 ──┤
   ├─→ ACC-03 ────────────┴─→ ACC-04 ──→ ACC-06 ──→ ACC-10 ──→ ACC-13
   │                                  └─→ ACC-07 ──┘
   ├─→ ACC-08 (مستقل — يمكن مبكراً) ──→ ACC-09 ──→ ACC-13
   ├─→ ACC-11 ──→ ADM-01 (و ADM-02 بعد ACC-00 مباشرة)
   └─→ ACC-12 (بعد ACC-04)
ADM-03: مستقل تماماً — أي وقت بعد ACC-00
ADM-04: بعد ACC-01 + ACC-09
Track MK: موازٍ كامل في المحادثة الأخرى — صفر تداخل
```

**التقدم الكلي:** 10/33 مهام منجزة — ACC-12 (2026-10-29): مركز المزامنة offline + النسخ الاحتياطي + رأس المستند — 3 migrations (`acc_sync_queue` بحالات pending/sent/needs_review وفريد (network_owner_id, client_op_id) يجعل إعادة دفع الدفعة مجانية بلا ازدواج ترحيل + `acc_backups` ببصمة sha256 على الجداول + `acc_doc_header` صف مستأجر واحد) + 3 موديلات + `AccSyncService` بـ 13 نوع عملية مبيّضة يعيد كل عملية عبر خدمتها المالكة بنفس تحقق الـ controllers (collection/debt/pay/expense/transfer/dist.sale/pos.order/pos.withdrawal/pos.exchange/stock.adjust/purchase/return/damaged)، كل عملية في معاملة مستقلة، queued_at يعيد التاريخ الحقيقي، الفاشلة تركن needs_review دون إيقاف البقية + تفعيل خطاف `queueFailedOp` في `AccPostingService` بإضافة network_owner_id (post:{doc_type} قابل للإعادة من المركز) + `AccBackupService` تصدير JSON موقّع مرتّب أهل←أبناء واستعادة ذرّية بديل-كامل في معاملة واحدة بفصل FKs وفرض نطاق المستأجر المستعيد — الملف العابث يُرفض بالبصمة قبل لمس صف + `AccDocHeaderController` (GET/PUT + رفع/حذف/بث شعار خاص) + 14 مساراً (`/sync/pending|queue|push|{op}/retry|discard` + `/backup(s)`+import/download/restore + `/doc-header*` ) خلف sync.push لكل الأدوار وsync.read|manage/backup.*/settings.* للمالك والإدارة + فلاتر: `AccOfflineQueue` صندوق Hive `acc_offline_ops` + `isOfflineError` (لا طابور لردود 4xx) + `accWriteOrQueue` رُبط بكل مسارات الكتابة (تحصيل/دين/سداد/مصروف/تحويل/بيع موزع/طلبات POS/سحب/استبدال/تسوية) — انقطاع الشبكة يحفظ العملية برسالة عربية بدل الخطأ + `SyncApi` + `AccSyncEngine` (دفع الدفعة بـ ops كسلسلة JSON، إزالة sent/replayed، flag needs_review بالسبب، قفل منع التداخل) + `sync_providers.dart` + 3 شاشات خلف AccFeatureGate (مركز المزامنة بعدّادات وعمليات جهاز بحذف سحبياً وطابور خادم بإعادة/استبعاد · النسخ الاحتياطي بإنشاء/تنزيل/استيراد/استعادة بتأكيد · رأس المستند بنموذج ومعاينة حية وشعار) + 3 بلاطات في acc_home + flush تلقائي عند عودة الاتصال — 12 اختباراً/74 تأكيداً خضراء + 32 اختباراً للأدوار بلا انكسار + 6 اختبارات Flutter للطابور (enqueue/FIFO/remove/flagError/envelope/isOfflineError) + php -l + analyze نظيف على كامل features/accounting — صفر تعارض خارج acc_*. سابقاً ACC-10 (2026-10-29): شرائح الخصم + الأرصدة/السحوبات + إشعارات واتساب — 3 migrations (`acc_discount_tiers` بأربعة أنماط commission/points/profit_balance/direct_percent × أساس qty/amount + `acc_webhook_events` قوالب {placeholder} + discount_amount إضافية على acc_sales/acc_pos_orders) + `AccDiscountService` (ترشيح أعمق شريحة مطابقة — min الأعلى ثم sort_order ثم id) + `AccTierRewardWriter` (رصيد النقاط/الأرباح للـ POS داخل معاملة المستند نفسها) + `AccWebhookService` (render + dispatch بعد الالتزام + wa.me + دفع داخلي للمستخدم المرتبط + audit لكل إرسال) + تطبيق الشرائح ذرّياً داخل `AccDistService::sale` (الخصم على الصافي والعمولة على الصافي + مكافآت POS) و`AccPosOrderService::approve` (النقاط المدفوعة لا تتجاوز القيمة المخفَّضة وpoints_total تُجمَّد على المصروف الفعلي) + `notifications` في ردود sale/approve/collect + مسارات `/discount-tiers/*` + `/balances` + `/webhook-events/*` + `/notifications/debt-due` + `LoyaltyApi` + 3 شاشات (شرائح الخصم / الأرصدة والسحوبات بلسنتين / إشعارات واتساب بلسنتين مع فتح wa.me) + 11 اختباراً/87 تأكيداً خضراء (تطبيق شريحة الخصم، نقاط/أرباح/عمولة، سقف الدفع المسبق، dispatch القوالب، تذكير الديون، الأرصدة، دورة السحب) + 60 اختباراً سابقاً بلا انكسار + php -l + analyze نظيف. سابقاً ACC-11 (2026-10-29): اشتراك المحاسبة طرف التطبيق بنمط mikrotik المُثبَت — 4 migrations (acc_plans بلا مستأجر ككتالوج مشرف + acc_payment_requests/acc_subscriptions مربوطة بـ network_owner_id لتغطية المالك ووكلائه + بذر إعدادات acc.trial_days=30/acc.enforce=0/acc.free_features/acc.pricing_note/acc.trial_is_paid) + 3 موديلات + `AccBillingController` (ensureTrial كسول بلا إعادة تجربة بعد انتهاء تاريخي، entitlements يقلب المنتهي لـ expired ويعيد المفاتيح المجانية فقط، دفع محفظة بقفل lockForUpdate + WalletLog debit بـ reference_type=acc_subscription داخل معاملة ذرّية، طلب تحويل بإيصال — pending واحد لكل مستأجر + إشعار أدمن) + مسارات `/billing/*` — entitlements مفتوحة لكل أدوار السياق وplans/payments/subscribe خلف `billing.*` (المالك/الإدارة فقط — موزع وPOS يُرفضان 403) + `AccBillingApi` + `AccEntitlementService` (allow-all حتى enforce=1 — نفس عقد EntitlementService بالضبط) + `AccFeatureGate`/`AccPremiumLockCard` (Paywall موحد يوجّه لشاشة الاشتراك — صفر لمس لـ router.dart) + `AccSubscriptionScreen` (حالة+باقات+دفع محفظة/تحويل+طلبات سابقة+pricing_note) + ربط acc_home وdist_home بالبوابة الجديدة وبلاطة «الاشتراك والباقات» — 12 اختباراً/78 تأكيداً خضراء (تجربة/idempotency/دفع/رصيد ناقص/باقة معطلة/طلب مكرر/أدوار/عزل مستأجر) + php -l + analyze نظيف على ملفات المحاسبة. سابقاً ACC-08 (2026-10-29): ترحيل مبيعات تطبيق العميل — migration `acc_posting_map` + موديل `AccPostingMap` (ربط مصدر→حسابات بـ JSON overlay على افتراضيات دليل الحسابات) + حارس `AccPlatformReadOnly` (المنع أمنياً: مستمع استعلامات يرمي أي insert/update/delete/DDL على transactions/transaction_cards/cards/card_categories/wallet_logs/networks/users/wallets أثناء التزامن — الاستثناء داخل معاملة البيع يردّها كلياً) + `AccPlatformSalesService` يفحص `transactions` (status=completed، غير سلفني) لشبكات المالك → قيد `card_purchase_platform` متوازن (Dr صافي المنصة cash_account + Dr عمولة commission_account ← Cr إيراد revenue_account + ساقا COGS Dr مصروف/Cr مخزون عند توفر تكلفة) + حركة مخزون `in`+`sale` لكل كرت بمرجع (card, id) — توقيع مطابق لمزامنة الراوتر فلا ازدواج أيّاً كان المسار السبّاق — والفائض بلا ربط كروت يُرحَّل بمرجع platform_transaction؛ idempotent بمفتاح `platform-sale-{tx}` + الفهرس الفريد للحركات؛ إعادة التشغيل مجانية؛ صف فاشل يُسجَّل في stats.errors ولا يوقف الباقي؛ الترحيل بالعملة الأساس شمال مع توثيق عملة الشبكة وسعرها في القيد + 4 مسارات (`GET /platform-sales` كسول المزامنة + `POST /platform-sales/sync` + `GET/PUT /posting-map` بتحقق وجود الحسابات) خلف صلاحيات platform.* للمالك/الإدارة — 11 اختباراً/73 تأكيداً خضراء (بيع محفظة حقيقي الشكل، توازن القيد، replay، سلفني/معلّق/فاشل مستثنى، كرت مايكروتيك بلا ازدواج بالاتجاهين، الحارس يرفض الكتابة ويردّها، الجداول سليمة، خريطة الحسابات تعمل، جنوب→شمال، عزل مستأجر). سابقاً ACC-02 (2026-10-27): المخزون والفئات كاملة — 8 migrations + `AccStockService` (حركات موقّعة لا تُحذف + رصيد مقفل + متوسط تكلفة مرجّح + تسوية مطلقة + مشتريات/تالف/مرتجع بقيد متوازن في معاملة واحدة) + `syncRouterCards` يقرأ `cards source=mikrotik` قراءة-فقط ويرحّلها للمخزون تلقائياً (in/sale موقّعة بـ ref فريد — إعادة التشغيل مجانية) + إنشاء فئات acc مرتبطة تلقائياً + 6 controllers + 20 مساراً + شاشتا «الفئات» و«المخزون» (أرصدة/حركات/تسوية/مزامنة يدوية) — 13 اختباراً/89 تأكيداً + analyze نظيف + ADB live. سابقاً ACC-05: الحركة المالية كاملة — تحصيل/ديون+سداد ذري/صناديق+تحويلات/مصروفات+فئات، كل حدث قيد متوازن في معاملة واحدة (collection/adjustment/transfer/expense)، رصيد افتتاحي للصناديق كقيد Dr صندوق/Cr حقوق ملكية، إلغاء المصروف بقيد عكسي، تعدد عملات عبر ExchangeRateSetting قراءة-فقط (ترحيل دائماً بالأساس شمال)، idempotency على التحصيل/التحويل/المصروف، 16 اختباراً/94 تأكيداً خضراء + analyze نظيف.
