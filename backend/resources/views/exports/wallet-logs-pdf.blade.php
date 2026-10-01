<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تقرير سجل المحافظ</title>
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
    <h2>تقرير سجل المحافظ</h2>
    <div class="meta">
        @if($from ?? null) من تاريخ: {{ $from }} @endif
        @if($until ?? null) &nbsp; إلى تاريخ: {{ $until }} @endif
    </div>

    <table>
        <thead>
            <tr>
                <th>#</th>
                <th>المستخدم</th>
                <th>الهاتف</th>
                <th>المنطقة</th>
                <th>النوع</th>
                <th>المبلغ</th>
                <th>الرصيد قبل</th>
                <th>الرصيد بعد</th>
                <th>الوصف</th>
                <th>التاريخ</th>
            </tr>
        </thead>
        <tbody>
            @foreach($records as $index => $row)
                @php
                    $regionType = $row->user?->region?->type;
                    $regionLabel = match($regionType) { 'north' => 'الشمال', 'south' => 'الجنوب', default => '—' };
                    $type = match($row->type) {
                        'credit' => 'إيداع',
                        'debit' => 'خصم',
                        'pending_topup' => 'طلب شحن (بانتظار المراجعة)',
                        'rejected_topup' => 'طلب شحن مرفوض',
                        default => $row->type,
                    };
                @endphp
                <tr>
                    <td>{{ $index + 1 }}</td>
                    <td>{{ $row->user?->name ?? '—' }}</td>
                    <td>{{ $row->user?->phone ?? '—' }}</td>
                    <td>{{ $regionLabel }}</td>
                    <td>{{ $type }}</td>
                    <td>{{ number_format($row->amount, 0) }} ريال</td>
                    <td>{{ number_format($row->balance_before, 0) }}</td>
                    <td>{{ number_format($row->balance_after, 0) }}</td>
                    <td>{{ $row->description }}</td>
                    <td>{{ $row->created_at?->format('Y-m-d H:i') }}</td>
                </tr>
            @endforeach
        </tbody>
    </table>
</body>
</html>
