<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('topup_service_settings', function (Blueprint $table) {
            $table->id();
            $table->string('code', 40)->unique();
            $table->string('name_ar');
            $table->string('category', 20);          // mobile | landline | utility | game | wholesale
            $table->string('provider_endpoint', 40); // yem, mtn, electwater, gameswcards, ...
            $table->string('account', 10)->default('south');
            $table->string('fee_type', 10)->default('none'); // none | percent | fixed
            $table->decimal('fee_value', 12, 2)->default(0); // percent (0-100) or fixed amount
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->json('meta')->nullable();        // per-service UI config (fields, hints)
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('topup_service_settings');
    }
};
