<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet «سلفني» credit state per subscriber (CYB-06).
     * `limit_amount` defaults to config('cyber.credit.default_limit')
     * when the row is lazily created and can be raised per subscriber
     * by ops; `outstanding` is the unpaid borrowed balance that is
     * collected automatically from the next incoming top-up/transfer.
     * The row is the lock point for borrow/repay serialisation.
     */
    public function up(): void
    {
        Schema::create('cyber_credit_limits', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('subscriber_id')->unique();
            $table->decimal('limit_amount', 14, 2);
            $table->decimal('outstanding', 14, 2)->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_credit_limits');
    }
};
