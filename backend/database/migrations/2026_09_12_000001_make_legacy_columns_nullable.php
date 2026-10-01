<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasColumn('daily_offers', 'category_id')) {
            DB::statement("ALTER TABLE daily_offers MODIFY category_id BIGINT UNSIGNED NULL");
        }
        if (Schema::hasColumn('daily_offers', 'start_date')) {
            DB::statement("ALTER TABLE daily_offers MODIFY start_date TIMESTAMP NULL");
        }
        if (Schema::hasColumn('daily_offers', 'end_date')) {
            DB::statement("ALTER TABLE daily_offers MODIFY end_date TIMESTAMP NULL");
        }
        if (Schema::hasColumn('advertisements', 'title')) {
            DB::statement("ALTER TABLE advertisements MODIFY title VARCHAR(255) NULL");
        }
    }

    public function down(): void
    {
        //
    }
};
