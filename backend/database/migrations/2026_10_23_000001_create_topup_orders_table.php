<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('topup_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('service_code', 40);      // yem, mtn, saba, post, elect, water, game_*, gomla_*
            $table->string('account', 10)->default('south'); // provider agent account used
            $table->string('target', 40);            // subscriber/customer number charged
            $table->decimal('amount', 12, 2);        // face value sent to provider
            $table->decimal('fee', 12, 2)->default(0);
            $table->decimal('total_charged', 12, 2); // amount + fee, in buyer currency
            $table->decimal('provider_price', 12, 2)->nullable(); // price reported by provider
            $table->string('transid', 40)->unique(); // provider transaction id (idempotency key)
            $table->string('provider_ref_id', 40)->nullable();
            $table->string('status', 20)->default('pending'); // pending|done|failed|banned
            $table->string('result_code', 10)->nullable();
            $table->string('result_desc', 500)->nullable();
            $table->json('request_payload')->nullable();
            $table->json('provider_response')->nullable();
            $table->boolean('refunded')->default(false);
            $table->timestamps();

            $table->index(['user_id', 'created_at']);
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('topup_orders');
    }
};
