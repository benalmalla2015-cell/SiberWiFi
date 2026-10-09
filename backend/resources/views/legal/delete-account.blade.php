<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="طلب حذف الحساب - سايبر WiFi">
    <title>طلب حذف الحساب | سايبر WiFi</title>
    <style>
        :root { color-scheme: light; --primary: #1e2d7d; --accent: #f8b803; --text: #172033; --muted: #64748b; --surface: #fff; --bg: #f4f6fb; --border: #e2e8f0; --error: #b91c1c; --success: #15803d; }
        * { box-sizing: border-box; }
        body { margin: 0; font-family: Tahoma, Arial, sans-serif; color: var(--text); background: var(--bg); line-height: 1.9; }
        header { background: linear-gradient(135deg, #111b52, var(--primary)); color: #fff; padding: 40px 20px; text-align: center; }
        header h1 { margin: 0 0 8px; font-size: clamp(1.7rem, 5vw, 2.5rem); }
        header p { margin: 0; opacity: .88; }
        main { width: min(720px, calc(100% - 28px)); margin: 24px auto; background: var(--surface); padding: clamp(22px, 5vw, 40px); border-radius: 18px; box-shadow: 0 12px 36px rgba(30,45,125,.08); }
        .notice { background: #fff8dc; border-right: 4px solid var(--accent); padding: 14px 18px; border-radius: 8px; margin-bottom: 24px; }
        .success { background: #dcfce7; border-right: 4px solid var(--success); color: var(--success); padding: 14px 18px; border-radius: 8px; margin-bottom: 24px; }
        label { display: block; margin-bottom: 6px; font-weight: 600; color: #293b8f; }
        input[type="text"], textarea, select { width: 100%; padding: 12px 14px; border: 1px solid var(--border); border-radius: 10px; font-family: inherit; font-size: 1rem; }
        textarea { resize: vertical; min-height: 110px; }
        .field { margin-bottom: 18px; }
        .radio-group { display: flex; gap: 16px; flex-wrap: wrap; }
        .radio-group label { display: flex; align-items: center; gap: 8px; font-weight: normal; cursor: pointer; }
        button { background: var(--error); color: #fff; border: none; padding: 12px 28px; border-radius: 10px; font-size: 1rem; font-weight: 600; cursor: pointer; }
        button:hover { opacity: .92; }
        .muted { color: var(--muted); font-size: .92rem; margin-top: 18px; }
        a { color: var(--primary); }
        footer { text-align: center; color: var(--muted); padding: 8px 20px 32px; }
    </style>
</head>
<body>
<header>
    <h1>طلب حذف الحساب</h1>
    <p>سايبر WiFi وتطبيق سايبر WiFi - إدارة الشبكات</p>
</header>
<main>
    @if (session('success'))
        <div class="success">
            تم استلام طلب حذف الحساب بنجاح. سيتم معالجته والتواصل معك عند الحاجة.
        </div>
    @endif

    <div class="notice">
        <strong>ملاحظة مهمة:</strong> يمكنك حذف حسابك فوراً من داخل التطبيق عبر المسار: حسابي ← حذف الحساب. إذا لم تتمكن من الوصول للتطبيق، يمكنك تقديم الطلب هنا.
    </div>

    <form method="POST" action="{{ route('delete-account.submit') }}">
        @csrf
        <div class="field">
            <label for="phone">رقم الهاتف المرتبط بالحساب</label>
            <input id="phone" name="phone" type="text" value="{{ old('phone') }}" placeholder="مثال: 700000001" required>
            @error('phone')<small style="color:var(--error)">{{ $message }}</small>@enderror
        </div>

        @php
            $appSel = old('app_type') ?: match (request('app')) {
                'owner', 'network_owner', 'network_owner_app' => 'network_owner_app',
                default => 'customer_app',
            };
        @endphp
        <div class="field">
            <label>التطبيق</label>
            <div class="radio-group">
                <label>
                    <input type="radio" name="app_type" value="customer_app" {{ $appSel === 'customer_app' ? 'checked' : '' }} required>
                    سايبر WiFi (تطبيق العميل)
                </label>
                <label>
                    <input type="radio" name="app_type" value="network_owner_app" {{ $appSel === 'network_owner_app' ? 'checked' : '' }} required>
                    سايبر WiFi - إدارة الشبكات
                </label>
            </div>
            @error('app_type')<small style="color:var(--error)">{{ $message }}</small>@enderror
        </div>

        <div class="field">
            <label for="notes">ملاحظات إضافية (اختياري)</label>
            <textarea id="notes" name="notes" placeholder="يمكنك ذكر سبب الحذف أو أي معلومة تساعدنا...">{{ old('notes') }}</textarea>
            @error('notes')<small style="color:var(--error)">{{ $message }}</small>@enderror
        </div>

        <button type="submit">تقديم طلب حذف الحساب</button>
    </form>

    <p class="muted">
        عند الحذف، تُحذف بيانات الحساب الشخصية ويُلغى ربط الجهاز. قد نحتفظ بسجلات المعاملات المالية والفوترة لفترة محدودة وفقاً للمتطلبات القانونية والضريبية. للاستفسارات: <a href="mailto:info@saiberwifi.net">info@saiberwifi.net</a>.
    </p>
</main>
<footer>© {{ date('Y') }} سايبر WiFi. جميع الحقوق محفوظة.</footer>
</body>
</html>
