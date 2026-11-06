# routes/cyber — CyberNet route fragments (Track CYB)

كل مهمة CYB تسجّل مساراتها في ملف مستقل هنا — `api_cyber.php` يحمّل كل
`*.php` تلقائياً تحت البادئة `/api/cyber` والاسم `cyber.`.

قواعد:
- ملف واحد لكل مجال: `register.php`, `billing.php`, `agent.php`, `hosts.php` …
- لا تعدّل `api_cyber.php` ولا أي ملف غير ملفك.
- المسارات العامة (تسجيل عميل جديد) توضع داخل fragment مع
  `->middleware('guest:sanctum')` أو تعريف بديل حسب قرار المصادقة —
  موثّق في cyber_plan/PLAN.md §6.
