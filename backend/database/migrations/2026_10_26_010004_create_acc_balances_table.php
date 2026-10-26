<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Aggregated balance per party — updated atomically inside the
     * same transaction as its journal entry (PLAN §3). Positive =
     * the party owes the owner / box holds cash (debit − credit).
     */
    public function up(): void
    {
        Schema::create('acc_balances', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('party_type', 20);
            $table->unsignedBigInteger('party_id');
            $table->decimal('balance', 18, 2)->default(0);
            $table->timestamps();

            $table->unique(['network_owner_id', 'party_type', 'party_id'], 'acc_balances_party_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_balances');
    }
};
