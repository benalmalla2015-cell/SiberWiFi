<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('networks', function (Blueprint $table) {
            if (!Schema::hasColumn('networks', 'code')) {
                $table->string('code', 20)->nullable()->after('id');
            }
        });

        // Backfill a unique code for existing networks based on their ID.
        DB::table('networks')
            ->where(fn ($q) => $q->whereNull('code')->orWhere('code', ''))
            ->orderBy('id')
            ->select('id')
            ->cursor()
            ->each(function ($network) {
                DB::table('networks')->where('id', $network->id)->update([
                    'code' => 'SW-' . str_pad((string) $network->id, 6, '0', STR_PAD_LEFT),
                ]);
            });

        Schema::table('networks', function (Blueprint $table) {
            $table->unique('code');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('networks', function (Blueprint $table) {
            $table->dropUnique(['code']);
            $table->dropColumn('code');
        });
    }
};
