<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Expense categories (PLAN §2.3) — per-tenant vocabulary for
     * the expenses screen. Seeded lazily with the usual network
     * costs (رواتب/إيجار/وقود/صيانة/إنترنت) on first use.
     */
    public function up(): void
    {
        Schema::create('acc_expense_categories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('name');
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['network_owner_id', 'name'], 'acc_expense_categories_name_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_expense_categories');
    }
};
