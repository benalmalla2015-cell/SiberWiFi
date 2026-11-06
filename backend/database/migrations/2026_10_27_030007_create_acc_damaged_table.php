<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Damaged/lost cards register (PLAN §2.1). Posting one writes a
     * negative `damaged` stock movement and a `damaged` journal
     * entry (expense ← inventory) atomically.
     */
    public function up(): void
    {
        Schema::create('acc_damaged', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('category_id')
                ->constrained('acc_card_categories')
                ->restrictOnDelete();
            $table->decimal('qty', 15, 2);
            $table->decimal('unit_cost', 15, 4)->default(0);
            $table->string('reason')->nullable();
            $table->string('evidence_note')->nullable();
            $table->date('date');
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->timestamps();

            $table->index(['network_owner_id', 'date'], 'acc_damaged_owner_date');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_damaged');
    }
};
