<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet subscriber wallets (CYB-04, PLAN §6.1).
     *
     * One wallet per digital subscriber, balance in YER. `subscriber_id`
     * references cyber_subscribers.id (CYB-03) — kept un-constrained on
     * purpose because the two tracks ship in parallel; a follow-up
     * additive migration may add the FK once both tables exist.
     */
    public function up(): void
    {
        Schema::create('cyber_wallets', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('subscriber_id')->unique();
            $table->decimal('balance', 14, 2)->default(0);
            $table->char('currency', 3)->default('YER');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_wallets');
    }
};
