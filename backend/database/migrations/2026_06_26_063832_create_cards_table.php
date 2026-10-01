<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('cards', function (Blueprint $table) {
            $table->id();
            $table->foreignId('category_id')->constrained('card_categories')->cascadeOnDelete();
            $table->foreignId('network_id')->constrained()->cascadeOnDelete();
            $table->string('card_number')->unique();
            $table->string('serial_number')->nullable();
            $table->enum('status', ['available', 'sold', 'reserved', 'expired'])->default('available');
            $table->foreignId('sold_to')->nullable()->constrained('users')->nullOnDelete();
            $table->unsignedBigInteger('transaction_id')->nullable();
            $table->timestamp('sold_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();
        });
        Schema::table('cards', function (Blueprint $table) {
            $table->index(['category_id', 'status']);
            $table->index(['network_id', 'status']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('cards');
    }
};
