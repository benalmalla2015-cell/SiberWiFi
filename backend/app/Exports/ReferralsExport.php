<?php

namespace App\Exports;

use App\Models\Referral;
use Illuminate\Database\Eloquent\Builder;
use Maatwebsite\Excel\Concerns\FromQuery;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithMapping;
use Maatwebsite\Excel\Concerns\WithStyles;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

class ReferralsExport implements FromQuery, WithHeadings, WithMapping, WithStyles
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
            : Referral::query();

        return $query
            ->with(['referrer.region', 'referred.region'])
            ->when($this->from, fn ($q) => $q->whereDate('created_at', '>=', $this->from))
            ->when($this->until, fn ($q) => $q->whereDate('created_at', '<=', $this->until))
            ->when($this->regionType, fn ($q, $value) => $q->whereHas(
                'referrer.region',
                fn ($r) => $r->where('type', $value)
            ))
            ->latest();
    }

    public function headings(): array
    {
        return [
            '#',
            'صاحب الرابط',
            'هاتف صاحب الرابط',
            'منطقة صاحب الرابط',
            'المسجل عبر الرابط',
            'هاتف المسجل',
            'منطقة المسجل',
            'مبلغ العمولة',
            'نسبة العمولة',
            'حالة الدفع',
            'تاريخ الإحالة',
        ];
    }

    public function map($row): array
    {
        $referrerRegion = $row->referrer?->region?->type;
        $referredRegion = $row->referred?->region?->type;

        return [
            $row->id,
            $row->referrer?->name ?? '—',
            $row->referrer?->phone ?? '—',
            match ($referrerRegion) {
                'north' => 'الشمال',
                'south' => 'الجنوب',
                default => '—',
            },
            $row->referred?->name ?? '—',
            $row->referred?->phone ?? '—',
            match ($referredRegion) {
                'north' => 'الشمال',
                'south' => 'الجنوب',
                default => '—',
            },
            number_format($row->commission_amount, 0),
            $row->commission_percentage,
            $row->is_paid ? 'مدفوعة' : 'غير مدفوعة',
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
