<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('commission_settings', function (Blueprint $table) {
            $table->enum('region_type', ['north', 'south'])->nullable()->after('type');
            $table->decimal('fixed_amount', 15, 2)->default(0)->after('percentage');
        });

        DB::table('commission_settings')->where('type', 'referral')->delete();
        DB::table('commission_settings')->insert([
            ['name' => 'عمولة الإحالات - الشمال', 'type' => 'referral', 'region_type' => 'north', 'fixed_amount' => 25, 'percentage' => 0, 'is_active' => true, 'is_global' => true, 'created_at' => now(), 'updated_at' => now()],
            ['name' => 'عمولة الإحالات - الجنوب', 'type' => 'referral', 'region_type' => 'south', 'fixed_amount' => 25, 'percentage' => 0, 'is_active' => true, 'is_global' => true, 'created_at' => now(), 'updated_at' => now()],
        ]);
    }

    public function down(): void
    {
        Schema::table('commission_settings', function (Blueprint $table) {
            $table->dropColumn(['region_type', 'fixed_amount']);
        });
    }
};
