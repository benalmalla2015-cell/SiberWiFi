# صيغ التكليف الجاهزة — انسخ والصق في محادثة جديدة

> **الاستخدام:** انسخ البلوك كاملاً للمهمة المطلوبة والصقه في محادثة جديدة مع الوكيل.
> **القاعدة للمنفّذ:** اقرأ أولاً `testapp/accounting_plan/PLAN.md` (§0 عقد العزل إلزامي) ثم `TASKS.md`.
> **بعد الإنجاز:** المنفّذ يحدّث حالة المهمة في `TASKS.md` + سجل الإنجاز في `PLAN.md` + يرسل task_complete لصندوق shared.

## ⚠️ بيانات الوصول المطلوبة لكل مهمة

| المرحلة | الوصول المطلوب |
|---|---|
| ACC-00 → ACC-12 (كل التطوير) | **لا شيء** — بيئة `testapp` المحلية + محاكي `tools/routeros_sim.py` كافية تماماً |
| MK-01 → MK-15 | لا شيء — المحاكي المحلي + ADB على الجهاز |
| ADM-01 → ADM-04 | لا شيء للتطوير — Filament في `testapp/backend` محلياً |
| **ACC-13 فقط** (إطلاق staging) | ✅ **هنا** تزوّدنا بيانات staging/الاستضافة — ستُطلب عندها |
| اختبار لايف ضد سيرفر staging (اختياري لأي مهمة) | تزوّدنا عند الحاجة — الافتراضي اختبار محلي |

---

## صيغ المحاسبة (ACC)

```
مهمتك: ACC-00 — التأسيس المعزول لنظام المحاسبة
المرجع الإلزامي قبل أي عمل: testapp/accounting_plan/PLAN.md (§0 عقد العزل) + testapp/accounting_plan/TASKS.md (صف ACC-00)
النطاق: app/Providers/AccountingServiceProvider.php + bootstrap/providers.php (سطر) + routes/api_accounting.php + مفاتيح acc.* في feature_keys.dart + مسار /accounting في router.dart + بطاقة دخول "المحاسبة" خلف FeatureGate + شاشة placeholder
القواعد الذهبية ملزمة: لا تعديل على auth/wallet/transactions/orders ولا أي ملف خارج النطاق — صفر تغيير سلوكي
عند الإنجاز: flutter analyze نظيف + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-01 — النواة المحاسبية (حسابات + قيود + ترحيل ذرّي)
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §2.3 + §3) + TASKS.md (صف ACC-01)
النطاق: migrations جداول acc_accounts, acc_journal_entries/lines, acc_balances, acc_audit_log + AccPostingService + idempotency + اختبارات توازن القيود
القواعد: جداول acc_* فقط، additive، قراءة فقط من الجداول القائمة، لا تلمس auth/wallet/transactions — صفر تعارض مع أي مهمة أخرى
عند الإنجاز: اختبارات وحدة خضراء + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-02 — المخزون وفئات الكروت
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §2.1) + TASKS.md (صف ACC-02)
النطاق: acc_card_categories, acc_stock, acc_stock_movements, acc_purchases, acc_suppliers, acc_returns, acc_damaged, acc_card_imports + شاشتا المخزون والفئات + ترحيل كروت source=mikrotik تلقائياً
القواعد: acc_* فقط + features/accounting/ فقط — لا تلمس cards/transactions للكتابة — صفر تعارض
عند الإنجاز: analyze نظيف + ADB live + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-03 — الوكلاء ونقاط البيع (الأدوار الثلاثة)
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §1 + §2.2) + TASKS.md (صف ACC-03)
النطاق: acc_agents (admin|distributor|pos مربوط بـ users) + acc_pos_points + acc_pos_devices + شاشتا المستخدمون ونقاط البيع + سياسات acc:*
القواعد: acc_* فقط — لا جداول auth جديدة — صفر تعارض
عند الإنجاز: تحقق دخول كل دور + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-04 — طلبات نقاط البيع (طلب/اعتماد/رفض)
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §2.2 + §3) + TASKS.md (صف ACC-04)
النطاق: acc_pos_orders(+items) + acc_points_ledger + acc_profit_ledger + واجهتا الطلب والاعتماد + ترحيل معاملة DB واحدة
القواعد: ذرّية كاملة + idempotency — acc_* فقط — صفر تعارض
عند الإنجاز: اختبار دورة كاملة + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-05 — الحركة المالية (تحصيلات/ديون/صناديق/مصروفات)
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §2.3 + §2.5) + TASKS.md (صف ACC-05)
النطاق: acc_collections + acc_debts(+payments) + acc_cash_boxes(+transfers) + acc_expenses(+categories) + شاشاتها + قيود تلقائية
القواعد: acc_* فقط، تعدد عملات عبر ExchangeRateSetting قراءة فقط — صفر تعارض
عند الإنجاز: تحقق القيود + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-06 — واجهة الموزع كاملة
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §1 + §5) + TASKS.md (صف ACC-06)
النطاق: dist_home (بيع نقد/آجل لنقاط البيع + متبقٍّ يومي) + طلبات/تحصيل/مديونيات/تقرير + acc_commissions
القواعد: features/accounting/ فقط — ترحيل عبر AccPostingService فقط — صفر تعارض
عند الإنجاز: ADB live للدور + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-07 — واجهة نقطة البيع كاملة
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §1 + §5) + TASKS.md (صف ACC-07)
النطاق: pos_home (نقاط+أرباح) + حزم الطلب + acc_withdrawals + acc_card_exchanges + سجل التحصيلات
القواعد: features/accounting/ فقط — ترحيل عبر AccPostingService — صفر تعارض
عند الإنجاز: ADB live للدور + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-08 — ترحيل مبيعات تطبيق العميل للمحاسبة
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §3) + TASKS.md (صف ACC-08)
النطاق: acc_posting_map + خدمة تقرأ transactions/cards **قراءة فقط** → قيد card_purchase_platform + حركة مخزون + idempotency
القواعد الحرجة: ممنوع أي update/insert/delete على transactions/wallet_logs/cards — المنع أمنياً في الكود — صفر تعارض
عند الإنجاز: اختبار بيع حقيقي يظهر قيداً دون تكرار + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-09 — التقارير وسجل التتبع
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §4 + §5) + TASKS.md (صف ACC-09)
النطاق: ملخص تنفيذي + كشف تحصيل يومي PDF + اتجاه 30 يوم + تحليل قوة POS + شاشة acc_audit_log + تقرير مبيعات/عمولات
القواعد: القراءة من acc_* فقط — صفر تعارض
عند الإنجاز: تطابق أرقام التقرير مع القيود + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-10 — شرائح الخصم + السحوبات + إشعارات واتساب
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §2.4 + §2.5) + TASKS.md (صف ACC-10)
النطاق: acc_discount_tiers (commission|points|profit|percent × qty|amount) + سحب أرصدة + اعتماد acc_withdrawals + acc_webhook_events بقوالب
القواعد: acc_* فقط — صفر تعارض
عند الإنجاز: اختبار تطبيق شريحة + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-11 — اشتراك المحاسبة (طرف التطبيق)
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §6) + TASKS.md (صف ACC-11) + نمط mikrotik_plans الموجود
النطاق: acc_plans/subscriptions/payment_requests migrations + API billing + شاشة الباقات + Paywall موحد + دفع محفظة (WalletLog acc_subscription) أو إيصال
القواعد: نفس نمط اشتراك المايكروتيك بالضبط — acc_* فقط — enforce=0 افتراضياً — صفر تعارض
عند الإنجاز: دورة اشتراك كاملة + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-12 — مركز المزامنة offline + النسخ الاحتياطي
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §2.5) + TASKS.md (صف ACC-12)
النطاق: acc_sync_queue (pending/sent/needs_review) + شاشة مركز المزامنة + acc_backups تصدير/استعادة + acc_doc_header
القواعد: acc_* فقط — صفر تعارض
عند الإنجاز: اختبار offline→مزامنة + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ACC-13 — التلميع وإطلاق staging (الإغلاق)
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§9 + §10 معايير القبول) + TASKS.md (صف ACC-13)
النطاق: UX/UI polish + أداء/فهارس + سيدر بيانات تجريبية + اختبارات شاملة + إطلاق staging
⚠️ بيانات استضافة staging: [ألصقها هنا — أزوّدك بها]
القواعد: staging فقط — الإنتاج ممنوع لمسه — صفر تعارض
عند الإنجاز: تقرير مطابقة معايير القبول §10 كاملاً + حدّث TASKS.md وPLAN.md
```

---

## صيغ لوحة المشرف (ADM)

```
مهمتك: ADM-01 — موارد Filament لاشتراكات المحاسبة
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §6) + TASKS.md (صف ADM-01)
النطاق: AccPlanResource + AccSubscriptionResource + AccPaymentRequestResource (موافقة/رفض ينشئ اشتراكاً ذرّياً) — مجموعة "المحاسبة"
القواعد: نفس نمط Mikrotik* Filament الموجود — app/Filament/Resources/Accounting/ فقط — صفر تعارض
عند الإنجاز: اختبار موافقة إيصال + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ADM-02 — إعدادات التحكم المركزي + خصومات/وكلاء في Filament
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §6.2) + TASKS.md (صف ADM-02)
النطاق: حقول acc.trial_days / acc.enforce / acc.free_features / acc.pricing_note في مورد الإعدادات + AccDiscountTierResource + AccAgentResource
القواعد: additive فقط — صفر تعارض
عند الإنجاز: تغيير trial_days ينعكس بالـ API + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ADM-03 — محاسبة المنصة (قراءة فقط)
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §6.5) + TASKS.md (صف ADM-03)
النطاق: لوحة دخل المنصة في Filament: إيرادات اشتراكات mikrotik+acc + عمولات + payouts + مصروفات + صافي بفترة + تصدير — Views فقط
القواعد الحرجة: قراءة فقط على الجداول المالية القائمة — ممنوع أي migration مالية — صفر تعارض
عند الإنجاز: تحقق أرقام + حدّث TASKS.md وPLAN.md ثم تقرير لي
```

```
مهمتك: ADM-04 — متابعة العمليات والأعطال في Filament
المرجع الإلزامي: testapp/accounting_plan/PLAN.md (§0 + §2.3 + §2.5) + TASKS.md (صف ADM-04)
النطاق: AccJournalEntryResource قراءة + عرض acc_audit_log + معالجة عناصر acc_sync_queue (needs_review)
القواعد: acc_* فقط — صفر تعارض
عند الإنجاز: حدّث TASKS.md وPLAN.md ثم تقرير لي
```

---

## صيغ المايكروتيك (MK) — للمحادثة الأخرى (تجميعات جاهزة)

```
مهمتك: مجموعة MK-A — MK-01 كروت UM v6/v7 + MK-02 أرشيف طباعة/إعادة دفعة + MK-10 نوع الاستخدام
المرجع الإلزامي: testapp/docs/ROADMAP.md + testapp/accounting_plan/PLAN.md (§0 + §7) + TASKS.md
النطاق: features/mikrotik/** فقط — لا تلمس features/accounting/ ولا جداول acc_*
القواعد: صفر تعارض مع مسار المحاسبة — المحاكي tools/routeros_sim.py للاختبار
عند الإنجاز: ADB live + حدّث TASKS.md + تقرير لي
```

```
مهمتك: مجموعة MK-B — MK-03 مضيف→عميل + MK-04 تشخيص موجّه بالأدلة + MK-13 الراوتر النشط
المرجع الإلزامي: testapp/docs/ROADMAP.md + testapp/accounting_plan/PLAN.md (§7) + TASKS.md
النطاق: features/mikrotik/** فقط — صفر تعارض مع المحاسبة
عند الإنجاز: ADB live على المحاكي + حدّث TASKS.md + تقرير لي
```

```
مهمتك: مجموعة MK-C — MK-05 الوصول عن بُعد + MK-11 Ping/DNS/NTP + MK-12 خريطة الأجهزة
المرجع الإلزامي: testapp/docs/ROADMAP.md + testapp/accounting_plan/PLAN.md (§7) + TASKS.md
النطاق: features/mikrotik/** فقط — صفر تعارض مع المحاسبة
عند الإنجاز: ADB live + حدّث TASKS.md + تقرير لي
```

```
مهمتك: مجموعة MK-D — MK-06 فوترة دورية/قطع تلقائي + MK-07 واتساب + MK-08 أبراج/معدات/فريق
المرجع الإلزامي: testapp/docs/ROADMAP.md + testapp/accounting_plan/PLAN.md (§7) + TASKS.md
النطاق: features/mikrotik/** فقط — صفر تعارض مع المحاسبة
عند الإنجاز: ADB live + حدّث TASKS.md + تقرير لي
```

```
مهمتك: مجموعة MK-E — MK-09 قفل PIN + MK-14 طباعة حرارية ESC/POS + MK-15 FTP ملفات
المرجع الإلزامي: testapp/docs/ROADMAP.md + testapp/accounting_plan/PLAN.md (§7) + TASKS.md
النطاق: features/mikrotik/** فقط — دقّق مكتبات vendor قبل الاستخدام — صفر تعارض
عند الإنجاز: ADB live + حدّث TASKS.md + تقرير لي
```

---

## ترتيب الفتح المقترح للمحادثات (أقصى توازي)

| الدفعة | المحادثات | ملاحظة |
|---|---|---|
| 1 | **ACC-00** وحده (حجز الملفات المشتركة) | إلزامي أولاً |
| 2 | ACC-01 + ACC-03 + ADM-02 + (MK-A بالمحادثة الأخرى) | بعد قفل A0 |
| 3 | ACC-02 + ACC-05 + ACC-08 + ADM-01 | تبعيات A1 محققة |
| 4 | ACC-04 + ACC-09 + ACC-11 + MK-B | |
| 5 | ACC-06 + ACC-07 + ACC-12 + MK-C | |
| 6 | ACC-10 + ADM-03 + ADM-04 + MK-D/E | |
| 7 | **ACC-13** الإغلاق + staging | هنا بيانات الاستضافة |
