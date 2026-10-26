# لوحة تتبع السبرنتات — المحاسبة + استكمال المايكروتيك

> حدّث الحالة عند إنجاز كل سبرنت. ⬜ لم يبدأ | 🔶 قيد التنفيذ | ✅ منجز | 🧪 باختبار | ⏸️ مؤجل
> المرجع التفصيلي: `PLAN.md` — سجل المهام المرقّم (ACC/ADM/MK): `TASKS.md`

## Track ACC — نظام المحاسبة (هذا المجلد)

| Sprint | النطاق | الملفات الأساسية | الحالة | ملاحظات |
|---|---|---|---|---|
| A0 | التأسيس المعزول (نقاط المشاركة تُجمَّد) | `bootstrap/providers.php`, `AccountingServiceProvider`, `routes/api_accounting.php`, `feature_keys.dart`, `router.dart`, بطاقة دخول | ⬜ | **يُنفَّذ قبل أي سبرنت آخر** |
| A1 | النواة: حسابات + قيود + ترحيل ذرّي + أرصدة + تدقيق | `acc_accounts`, `acc_journal_*`, `acc_balances`, `acc_audit_log`, `AccPostingService` | ⬜ | اختبارات توازن مدين/دائن إلزامية |
| A2 | المخزون والفئات | `acc_card_categories`, `acc_stock`, `acc_stock_movements`, `acc_purchases`, `acc_suppliers`, `acc_returns`, `acc_damaged`, `acc_card_imports` | ⬜ | شاشتا المخزون والفئات |
| A3 | الأطراف: وكلاء ونقاط بيع | `acc_agents`, `acc_pos_points`, `acc_pos_devices` | ⬜ | ربط بـ users الموجود |
| A4 | طلبات POS (طلب/اعتماد/رفض) | `acc_pos_orders(+items)`, `acc_points_ledger`, `acc_profit_ledger` | ⬜ | ترحيل معاملة واحدة |
| A5 | الحركة المالية | `acc_collections`, `acc_debts(+payments)`, `acc_cash_boxes(+transfers)`, `acc_expenses(+categories)` | ⬜ | |
| A6 | واجهة الموزع | `dist_*` screens + endpoints | ⬜ | نقد/آجل + متبقٍّ يومي |
| A7 | واجهة نقطة البيع | `pos_*` screens + `acc_withdrawals`, `acc_card_exchanges` | ⬜ | نقاط+أرباح |
| A8 | ترحيل بيع تطبيق العميل | `acc_posting_map` + خدمة القراءة من `transactions` | ⬜ | **قراءة فقط** — إمكانية التقديم مبكراً |
| A9 | التقارير والتتبع | reports endpoints + PDF كشف التحصيل + تحليل POS + audit screen | ⬜ | |
| A10 | خصومات/سحوبات/واتساب | `acc_discount_tiers`, `acc_webhook_events`, سحب أرصدة | ⬜ | |
| A11 | اشتراكات المحاسبة + Filament | `acc_plans`, `acc_subscriptions`, `acc_payment_requests`, `acc.*` settings | ⬜ | مستقل — يمكن تقديمه |
| A12 | مزامنة offline + نسخ احتياطي + رأس المستند | `acc_sync_queue`, `acc_backups`, `acc_doc_header` | ⬜ | |
| A13 | تلميع + إطلاق staging | UX/UI polish, performance, e2e | ⬜ | |

## Track MK — استكمال المايكروتيك (المحادثة الأخرى)

| Sprint | النطاق | الحالة |
|---|---|---|
| MK-A | M1 كروت UM v6/v7 · M2 أرشيف طباعة/إعادة دفعة · M10 نوع الاستخدام | ⬜ |
| MK-B | M3 مضيف→عميل · M4 تشخيص موجّه بالأدلة · M13 الراوتر النشط | ⬜ |
| MK-C | M5 الوصول عن بُعد (SSL/DDNS/VPN) · M11 Ping/DNS/NTP · M12 خريطة الأجهزة | ⬜ |
| MK-D | M6 فوترة دورية/قطع تلقائي · M7 واتساب · M8 أبراج/معدات/فريق | ⬜ |
| MK-E | M9 قفل PIN · M14 طباعة حرارية · M15 FTP ملفات | ⬜ |

## اختياري لاحقاً

| Sprint | النطاق | الحالة |
|---|---|---|
| ADM-1 | محاسبة لوحة المشرف (قراءة فقط فوق الموجود) | ⏸️ |

## قواعد التشغيل المتوازي

1. A0 أولاً ووحده — بعده كل المسارات حرة.
2. Commit لكل سبرنت برسالة واضحة + تحديث هذه اللوحة و`PLAN.md` سجل الإنجاز.
3. عند الحاجة لملف مشترك مجمّد: رسالة `question` للمسار الآخر عبر `.autoclaw`.
4. كل سبرنت: `flutter analyze` نظيف + اختبارات + لقطة ADB مؤرشفة في `live_test/`.
5. النشر على staging فقط — الإنتاج بدورة النشر المعتمدة.
