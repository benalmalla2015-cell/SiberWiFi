<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تقرير المعاملات</title>
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
    <h2>تقرير المعاملات</h2>
    <div class="meta">
        @if($from ?? null) من تاريخ: {{ $from }} @endif
        @if($until ?? null) &nbsp; إلى تاريخ: {{ $until }} @endif
    </div>

    <table>
        <thead>
            <tr>
                <th>#</th>
                <th>رقم المعاملة</th>
                <th>العميل</th>
                <th>الهاتف</th>
                <th>الشبكة</th>
                <th>المنطقة</th>
                <th>الفئة</th>
                <th>الكمية</th>
                <th>الإجمالي</th>
                <th>العمولة</th>
                <th>للمالك</th>
                <th>الحالة</th>
                <th>التاريخ</th>
            </tr>
        </thead>
        <tbody>
            @foreach($records as $index => $row)
                @php
                    $regionType = $row->user?->region?->type;
                    $regionLabel = match($regionType) { 'north' => 'الشمال', 'south' => 'الجنوب', default => '—' };
                    $status = match($row->status) {
                        'completed' => 'مكتملة',
                        'pending' => 'معلقة',
                        'failed' => 'فاشلة',
                        default => $row->status,
                    };
                @endphp
                <tr>
                    <td>{{ $index + 1 }}</td>
                    <td>{{ $row->transaction_number }}</td>
                    <td>{{ $row->user?->name ?? '—' }}</td>
                    <td>{{ $row->user?->phone ?? '—' }}</td>
                    <td>{{ $row->network?->name ?? '—' }}</td>
                    <td>{{ $regionLabel }}</td>
                    <td>{{ $row->category?->name ?? '—' }}</td>
                    <td>{{ $row->quantity }}</td>
                    <td>{{ number_format($row->total_amount, 0) }} ريال</td>
                    <td>{{ number_format($row->commission_amount, 0) }} ريال</td>
                    <td>{{ number_format($row->network_owner_amount, 0) }} ريال</td>
                    <td>{{ $status }}</td>
                    <td>{{ $row->created_at?->format('Y-m-d H:i') }}</td>
                </tr>
            @endforeach
        </tbody>
    </table>
</body>
</html>
