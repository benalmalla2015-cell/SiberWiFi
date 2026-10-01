<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تقرير الإحالات</title>
    <style>
        body { font-family: sans-serif; font-size: 11px; direction: rtl; }
        h2 { text-align: center; margin-bottom: 10px; }
        .meta { margin-bottom: 10px; font-size: 11px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { border: 1px solid #333; padding: 5px; text-align: right; }
        th { background-color: #f0f0f0; font-weight: bold; }
    </style>
</head>
<body>
    <h2>تقرير الإحالات</h2>
    <div class="meta">
        @if($from ?? null) من تاريخ: {{ $from }} @endif
        @if($until ?? null) &nbsp; إلى تاريخ: {{ $until }} @endif
    </div>

    <table>
        <thead>
            <tr>
                <th>#</th>
                <th>صاحب الرابط</th>
                <th>هاتف صاحب الرابط</th>
                <th>منطقة صاحب الرابط</th>
                <th>المسجل عبر الرابط</th>
                <th>هاتف المسجل</th>
                <th>منطقة المسجل</th>
                <th>مبلغ العمولة</th>
                <th>نسبة العمولة</th>
                <th>حالة الدفع</th>
                <th>تاريخ الإحالة</th>
            </tr>
        </thead>
        <tbody>
            @foreach($records as $index => $row)
                @php
                    $referrerRegion = $row->referrer?->region?->type;
                    $referredRegion = $row->referred?->region?->type;
                    $referrerRegionLabel = match($referrerRegion) { 'north' => 'الشمال', 'south' => 'الجنوب', default => '—' };
                    $referredRegionLabel = match($referredRegion) { 'north' => 'الشمال', 'south' => 'الجنوب', default => '—' };
                    $paymentStatus = $row->is_paid ? 'مدفوعة' : 'غير مدفوعة';
                @endphp
                <tr>
                    <td>{{ $index + 1 }}</td>
                    <td>{{ $row->referrer?->name ?? '—' }}</td>
                    <td>{{ $row->referrer?->phone ?? '—' }}</td>
                    <td>{{ $referrerRegionLabel }}</td>
                    <td>{{ $row->referred?->name ?? '—' }}</td>
                    <td>{{ $row->referred?->phone ?? '—' }}</td>
                    <td>{{ $referredRegionLabel }}</td>
                    <td>{{ number_format($row->commission_amount, 0) }} ريال</td>
                    <td>{{ $row->commission_percentage }}%</td>
                    <td>{{ $paymentStatus }}</td>
                    <td>{{ $row->created_at?->format('Y-m-d H:i') }}</td>
                </tr>
            @endforeach
        </tbody>
    </table>
</body>
</html>
