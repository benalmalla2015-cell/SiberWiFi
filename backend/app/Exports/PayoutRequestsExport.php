<?php

namespace App\Exports;

use App\Models\PayoutRequest;
use Illuminate\Database\Eloquent\Builder;
use Maatwebsite\Excel\Concerns\FromQuery;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithMapping;
use Maatwebsite\Excel\Concerns\WithStyles;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

class PayoutRequestsExport implements FromQuery, WithHeadings, WithMapping, WithStyles
{
    public function __construct(
        private ?Builder $baseQuery = null,
        private ?string $from = null,
        private ?string $until = null,
        private ?string $regionType = null,
    ) {}

    public function query(): Builder
    {
        $query = $this->baseQuery
            ? clone $this->baseQuery
            : PayoutRequest::query();

        return $query
            ->with(['user.region'])
            ->when($this->from, fn ($q) => $q->whereDate('created_at', '>=', $this->from))
            ->when($this->until, fn ($q) => $q->whereDate('created_at', '<=', $this->until))
            ->when($this->regionType, fn ($q, $value) => $q->whereHas(
                'user.region',
                fn ($r) => $r->where('type', $value)
            ))
            ->latest();
    }

    public function headings(): array
    {
        return [
            'رقم الطلب',
            'صاحب الشبكة',
            'الهاتف',
            'المنطقة',
            'المبلغ المطلوب',
            'المبلغ المدفوع',
            'الحالة',
            'تاريخ الطلب',
        ];
    }

    public function map($row): array
    {
        $regionType = $row->user?->region?->type;

        return [
            $row->request_number,
            $row->user?->name ?? '—',
            $row->user?->phone ?? '—',
            match ($regionType) {
                'north' => 'الشمال',
                'south' => 'الجنوب',
                default => '—',
            },
            number_format($row->amount, 0),
            number_format($row->paid_amount, 0),
            match ($row->status) {
                'pending' => 'قيد المراجعة',
                'approved' => 'تمت الموافقة',
                'paid_unconfirmed' => 'تم الصرف - بانتظار التأكيد',
                'received' => 'مكتمل',
                'rejected' => 'مرفوض',
                default => $row->status,
            },
            $row->created_at?->format('Y-m-d H:i'),
        ];
    }

    public function styles(Worksheet $sheet): array
    {
        return [
            1 => ['font' => ['bold' => true]],
        ];
    }
}
