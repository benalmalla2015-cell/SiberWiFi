<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** Card/package suppliers (PLAN §2.1). */
    public function up(): void
    {
        Schema::create('acc_suppliers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('name');
            $table->string('phone', 32)->nullable();
            $table->string('note')->nullable();
            $table->timestamps();

            $table->index(['network_owner_id', 'name'], 'acc_suppliers_owner_name');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_suppliers');
    }
};
