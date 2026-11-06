<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/*
|--------------------------------------------------------------------------
| CYB-13 — Soft-delete for account deletion (Google Play compliance)
|--------------------------------------------------------------------------
| DELETE /api/cyber/account removes the subscriber's personal data
| (documents, device binding, certificate identity) and soft-deletes the
| row so the audit trail (top-ups, commissions, host shares) stays
| intact for accounting while the account can no longer be used.
|
| Additive only: nullable column, no data changes, no effect on
| existing queries beyond excluding deleted subscribers.
*/
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('cyber_subscribers', function (Blueprint $table) {
            $table->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::table('cyber_subscribers', function (Blueprint $table) {
            $table->dropSoftDeletes();
        });
    }
};
