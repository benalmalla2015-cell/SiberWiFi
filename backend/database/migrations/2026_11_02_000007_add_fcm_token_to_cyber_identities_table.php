<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * FCM push token per enrolled device (CYB-04) — the subscriber has
     * no users-account, so top-up/service notifications are pushed to
     * the device bound by cyber_identities. The client app writes the
     * token after enrolment (CYB-05); nullable until then.
     */
    public function up(): void
    {
        Schema::table('cyber_identities', function (Blueprint $table) {
            $table->string('fcm_token')->nullable()->after('device_id')->index();
        });
    }

    public function down(): void
    {
        Schema::table('cyber_identities', function (Blueprint $table) {
            $table->dropIndex(['fcm_token']);
            $table->dropColumn('fcm_token');
        });
    }
};
