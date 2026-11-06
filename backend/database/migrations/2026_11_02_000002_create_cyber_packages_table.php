<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet packages (CYB-04, PLAN §4.2) — pilot price points:
     * day 200 YER, week 800 YER, month 1,500 YER, each with a data
     * quota. `rate_limit` is the Mikrotik-Rate-Limit value pushed to
     * subscribers on this package (null = billing default).
     *
     * The three pilot rows are seeded here so /api/cyber/packages is
     * useful the moment the table exists; the admin panel re-tunes
     * quotas/limits before launch (PLAN §4.2).
     */
    public function up(): void
    {
        Schema::create('cyber_packages', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('name_ar')->nullable();
            $table->unsignedSmallInteger('duration_days');
            $table->decimal('data_limit_gb', 10, 3)->nullable();
            $table->decimal('price', 12, 2);
            $table->string('rate_limit')->nullable();
            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['is_active', 'sort_order']);
        });

        DB::table('cyber_packages')->insert([
            [
                'name' => 'daily', 'name_ar' => 'باقة اليوم',
                'duration_days' => 1, 'data_limit_gb' => 1,
                'price' => 200, 'rate_limit' => null,
                'is_active' => true, 'sort_order' => 1,
                'created_at' => now(), 'updated_at' => now(),
            ],
            [
                'name' => 'weekly', 'name_ar' => 'باقة الأسبوع',
                'duration_days' => 7, 'data_limit_gb' => 7,
                'price' => 800, 'rate_limit' => null,
                'is_active' => true, 'sort_order' => 2,
                'created_at' => now(), 'updated_at' => now(),
            ],
            [
                'name' => 'monthly', 'name_ar' => 'باقة الشهر',
                'duration_days' => 30, 'data_limit_gb' => 30,
                'price' => 1500, 'rate_limit' => null,
                'is_active' => true, 'sort_order' => 3,
                'created_at' => now(), 'updated_at' => now(),
            ],
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_packages');
    }
};
