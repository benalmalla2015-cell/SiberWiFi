<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Simplified chart of accounts per network owner (Track ACC-01).
     * Purely additive — acc_* prefix, tenant-scoped, touches nothing else.
     */
    public function up(): void
    {
        Schema::create('acc_accounts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('code', 20);
            $table->string('name');
            $table->enum('type', ['asset', 'liability', 'equity', 'revenue', 'expense']);
            $table->string('parent_code', 20)->nullable();
            // Seeded defaults are system accounts — protected from deletion.
            $table->boolean('is_system')->default(false);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['network_owner_id', 'code']);
            $table->index(['network_owner_id', 'type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_accounts');
    }
};
