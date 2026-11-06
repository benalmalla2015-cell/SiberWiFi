<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Operating sub-accounts inside one network owner's tenant
     * (PLAN §1): admin | distributor | pos — bound to an existing
     * `users` account; the role decides which UI surface the same
     * owner app routes the employee to. No new auth tables.
     */
    public function up(): void
    {
        Schema::create('acc_agents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            // One user account = one agent identity across the system.
            $table->foreignId('user_id')
                ->unique()
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('role', 12); // admin|distributor|pos
            $table->string('display_name');
            $table->string('phone', 32)->nullable();
            // {"<category_id>": <max qty per day>} — enforced by ACC-04+.
            $table->json('daily_limit_per_category')->nullable();
            $table->boolean('cash_allowed')->default(true);
            $table->boolean('credit_allowed')->default(false);
            $table->string('status', 10)->default('active'); // active|suspended
            $table->string('commission_mode', 12)->nullable(); // none|percent|fixed|points
            $table->decimal('commission_value', 12, 2)->nullable();
            $table->timestamps();

            $table->index(['network_owner_id', 'status'], 'acc_agents_owner_status');
            $table->index(['network_owner_id', 'role'], 'acc_agents_owner_role');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_agents');
    }
};
