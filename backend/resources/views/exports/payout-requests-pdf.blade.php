<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تقرير طلبات السحب</title>
    <style>
        body { font-family: sans-serif; font-size: 12px; direction: rtl; }
        h2 { text-align: center; margin-bottom: 10px; }
        .meta { margin-bottom: 10px; font-size: 11px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { border: 1px solid #333; padding: 6px; text-align: right; }
        th { background-color: #f0f0f0; font-weight: bold; }
        .total { margin-top: 10px; font-weight: bold; }
    </style>
</head>
<body>
    <h2>تقرير طلبات السحب</h2>
    <div class="meta">
        @if($from ?? null) من تاريخ: {{ $from }} @endif
        @if($until ?? null) &nbsp; إلى تاريخ: {{ $until }} @endif
    </div>

    <table>
        <thead>
            <tr>
                <th>#</th>
                <th>رقم الطلب</th>
                <th>صاحب الشبكة</th>
                <th>الهاتف</th>
                <th>المنطقة</th>
                <th>المبلغ المطلوب</th>
                <th>المبلغ المدفوع</th>
                <th>الحالة</th>
                <th>تاريخ الطلب</th>
            </tr>
        </thead>
        <tbody>
            @php $totalRequested = 0; $totalPaid = 0; @endphp
            @foreach($records as $index => $row)
                @php
                    $regionType = $row->user?->region?->type;
                    $regionLabel = match($regionType) { 'north' => 'الشمال', 'south' => 'الجنوب', default => '—' };
                    $status = match($row->status) {
                        'pending' => 'قيد المراجعة',
                        'approved' => 'تمت الموافقة',
                        'paid_unconfirmed' => 'تم الصرف - بانتظار التأكيد',
                        'received' => 'مكتمل',
                        'rejected' => 'مرفوض',
                        default => $row->status,
                    };
                    $totalRequested += (float) $row->amount;
                    $totalPaid += (float) $row->paid_amount;
                @endphp
                <tr>
                    <td>{{ $index + 1 }}</td>
                    <td>{{ $row->request_number }}</td>
                    <td>{{ $row->user?->name ?? '—' }}</td>
                    <td>{{ $row->user?->phone ?? '—' }}</td>
                    <td>{{ $regionLabel }}</td>
                    <td>{{ number_format($row->amount, 0) }} ريال</td>
                    <td>{{ number_format($row->paid_amount, 0) }} ريال</td>
                    <td>{{ $status }}</td>
                    <td>{{ $row->created_at?->format('Y-m-d H:i') }}</td>
                </tr>
            @endforeach
        </tbody>
    </table>

    <div class="total">
        إجمالي المبلغ المطلوب: {{ number_format($totalRequested, 0) }} ريال
        &nbsp; | &nbsp;
        إجمالي المبلغ المدفوع: {{ number_format($totalPaid, 0) }} ريال
    </div>
</body>
</html>
