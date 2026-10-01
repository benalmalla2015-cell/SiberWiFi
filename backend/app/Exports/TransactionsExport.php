<?php

namespace App\Exports;

use App\Models\Transaction;
use Illuminate\Database\Eloquent\Builder;
use Maatwebsite\Excel\Concerns\FromQuery;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithMapping;
use Maatwebsite\Excel\Concerns\WithStyles;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

class TransactionsExport implements FromQuery, WithHeadings, WithMapping, WithStyles
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
            : Transaction::query();

        return $query
            ->with(['user.region', 'network:id,name', 'category:id,name'])
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
            '#',
            'العميل',
            'الهاتف',
            'الشبكة',
            'المنطقة',
            'الفئة',
            'الكمية',
            'الإجمالي',
            'عمولة المنصة',
            'صافي المالك',
            'الحالة',
            'التاريخ',
        ];
    }

    public function map($row): array
    {
        $regionType = $row->user?->region?->type;

        return [
            $row->id,
            $row->user?->name ?? '—',
            $row->user?->phone ?? '—',
            $row->network?->name ?? '—',
            match ($regionType) {
                'north' => 'الشمال',
                'south' => 'الجنوب',
                default => '—',
            },
            $row->category?->name ?? '—',
            $row->quantity,
            number_format($row->total_amount, 0),
            number_format($row->commission_amount, 0),
            number_format($row->network_owner_amount, 0),
            match ($row->status) {
                'completed' => 'مكتملة',
                'pending' => 'معلقة',
                'failed' => 'فاشلة',
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
