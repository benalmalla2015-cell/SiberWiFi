<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Accounting subscription plans (ACC-11, PLAN §6.1) — mirrors
     * mikrotik_plans exactly: admin-managed catalog, no tenant column.
     */
    public function up(): void
    {
        Schema::create('acc_plans', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->text('description')->nullable();
            $table->decimal('price', 12, 2);
            $table->string('currency', 10)->default('YER');
            $table->unsignedInteger('duration_days');
            // Premium acc.* feature keys this plan unlocks
            // (AccFeatures in feature_keys.dart).
            $table->json('features')->nullable();
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_plans');
    }
};
