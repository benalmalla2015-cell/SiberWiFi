<?php

namespace Database\Seeders;

use App\Models\CyberCoveragePoint;
use Illuminate\Database\Seeder;

/**
 * CyberNet coverage seed (CYB-08) — the pilot point: Al-Ma'alla, Aden
 * (PLAN §1 field trial, hosted on the founding HOST_PILOT router).
 * Idempotent on (name, city).
 */
class CyberCoveragePointSeeder extends Seeder
{
    public function run(): void
    {
        CyberCoveragePoint::updateOrCreate(
            ['name' => 'المعلا', 'city' => 'عدن'],
            [
                'host_name' => 'HOST_PILOT',
                'latitude' => 12.7889,
                'longitude' => 45.0064,
                'status' => CyberCoveragePoint::STATUS_ACTIVE,
                'sort_order' => 1,
            ]
        );
    }
}
