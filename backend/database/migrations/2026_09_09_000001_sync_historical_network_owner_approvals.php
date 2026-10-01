<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::table('network_owners')
            ->where(function ($query) {
                $query->where('is_approved', false)->orWhereNull('is_approved');
            })
            ->whereExists(function ($query) {
                $query->selectRaw('1')
                    ->from('networks')
                    ->whereColumn('networks.user_id', 'network_owners.user_id')
                    ->where('networks.status', 'active')
                    ->whereNull('networks.deleted_at');
            })
            ->update([
                'is_approved' => true,
                'approved_at' => DB::raw('COALESCE(approved_at, updated_at, created_at, CURRENT_TIMESTAMP)'),
                'updated_at' => now(),
            ]);
    }

    public function down(): void
    {
    }
};
