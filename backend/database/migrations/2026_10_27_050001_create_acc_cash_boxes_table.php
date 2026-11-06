<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Cash boxes (PLAN §2.3) — the physical drawers money moves
     * through. Every collection/expense/transfer touches a box,
     * and each box is tracked as a journal party (`party_type=box`)
     * so acc_balances mirrors the cash position per box.
     *
     * `balance` is kept in the box's own currency for display;
     * journal lines always post the base-normalized amount.
     */
    public function up(): void
    {
        Schema::create('acc_cash_boxes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('name');
            $table->string('currency', 10)->default('north');
            $table->decimal('balance', 15, 2)->default(0);
            $table->boolean('is_default')->default(false);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['network_owner_id', 'name'], 'acc_cash_boxes_name_unique');
            $table->index(['network_owner_id', 'is_active'], 'acc_cash_boxes_active');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_cash_boxes');
    }
};
