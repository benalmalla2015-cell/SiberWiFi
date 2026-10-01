<?php

namespace App\Exports;

use App\Models\User;
use Maatwebsite\Excel\Concerns\FromQuery;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithMapping;
use Maatwebsite\Excel\Concerns\WithStyles;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

class UsersExport implements FromQuery, WithHeadings, WithMapping, WithStyles
{
    public function __construct(private ?string $type = null) {}

    public function query()
    {
        return User::query()
            ->when($this->type, fn($q) => $q->where('type', $this->type))
            ->latest();
    }

    public function headings(): array
    {
        return ['#', 'الاسم', 'الهاتف', 'البريد الإلكتروني', 'النوع', 'الرصيد', 'المنطقة', 'نشط', 'تاريخ التسجيل'];
    }

    public function map($row): array
    {
        return [
            $row->id,
            $row->name,
            $row->phone,
            $row->email ?? '—',
            match($row->type) { 'client' => 'عميل', 'network_owner' => 'صاحب شبكة', 'charging_point' => 'نقطة شحن', 'admin' => 'مشرف', default => $row->type },
            number_format($row->balance, 0),
            $row->region_type === 'north' ? 'شمال' : 'جنوب',
            $row->is_active ? 'نعم' : 'لا',
            $row->created_at->format('Y-m-d'),
        ];
    }

    public function styles(Worksheet $sheet): array
    {
        return [1 => ['font' => ['bold' => true]]];
    }
}
