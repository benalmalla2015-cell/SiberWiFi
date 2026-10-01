<?php

namespace App\Exports;

use App\Models\WalletLog;
use Illuminate\Database\Eloquent\Builder;
use Maatwebsite\Excel\Concerns\FromQuery;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithMapping;
use Maatwebsite\Excel\Concerns\WithStyles;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

class WalletLogsExport implements FromQuery, WithHeadings, WithMapping, WithStyles
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
            : WalletLog::query();

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
            '#',
            'المستخدم',
            'الهاتف',
            'المنطقة',
            'النوع',
            'المبلغ',
            'الرصيد قبل',
            'الرصيد بعد',
            'الوصف',
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
            match ($regionType) {
                'north' => 'الشمال',
                'south' => 'الجنوب',
                default => '—',
            },
            match ($row->type) {
                'credit' => 'إيداع',
                'debit' => 'خصم',
                'pending_topup' => 'طلب شحن (بانتظار المراجعة)',
                'rejected_topup' => 'طلب شحن مرفوض',
                default => $row->type,
            },
            number_format($row->amount, 0),
            number_format($row->balance_before, 0),
            number_format($row->balance_after, 0),
            $row->description,
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
