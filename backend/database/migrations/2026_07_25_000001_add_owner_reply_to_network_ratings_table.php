<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('network_ratings', function (Blueprint $table) {
            if (!Schema::hasColumn('network_ratings', 'owner_reply')) {
                $table->text('owner_reply')->nullable()->after('review');
            }
            if (!Schema::hasColumn('network_ratings', 'replied_at')) {
                $table->timestamp('replied_at')->nullable()->after('owner_reply');
            }
        });
    }

    public function down(): void
    {
        Schema::table('network_ratings', function (Blueprint $table) {
            if (Schema::hasColumn('network_ratings', 'replied_at')) {
                $table->dropColumn('replied_at');
            }
            if (Schema::hasColumn('network_ratings', 'owner_reply')) {
                $table->dropColumn('owner_reply');
            }
        });
    }
};
