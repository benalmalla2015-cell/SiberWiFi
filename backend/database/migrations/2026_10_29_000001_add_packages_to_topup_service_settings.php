<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('topup_service_settings', function (Blueprint $table) {
            // Predefined packages shown as tappable cards in the app.
            // Each entry: {name, code, price, note}
            $table->json('packages')->nullable()->after('meta');
        });
    }

    public function down(): void
    {
        Schema::table('topup_service_settings', function (Blueprint $table) {
            $table->dropColumn('packages');
        });
    }
};
