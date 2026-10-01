<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (!Schema::hasColumn('users', 'region_id')) {
                $table->foreignId('region_id')->nullable()->after('region_type')->constrained('regions')->nullOnDelete();
            }
            if (!Schema::hasColumn('users', 'directorate_id')) {
                $table->foreignId('directorate_id')->nullable()->after('region_id')->constrained('directorates')->nullOnDelete();
            }
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (Schema::hasColumn('users', 'directorate_id')) {
                $table->dropConstrainedForeignId('directorate_id');
            }
            if (Schema::hasColumn('users', 'region_id')) {
                $table->dropConstrainedForeignId('region_id');
            }
        });
    }
};
