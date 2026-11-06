<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Discount/reward tiers (PLAN §2.4, Sprint ACC-10).
     *
     * One tier = one bracket: when a document's `basis` (total qty
     * or total amount) lands inside [min, max] — NULL max means an
     * open-ended top bracket — the `reward` applies automatically
     * inside the document's atomic posting:
     *
     *   mode direct_percent → discount off the document value
     *   mode points         → bonus points credited to the POS
     *   mode profit_balance → bonus profit credited to the POS
     *   mode commission     → extra commission for the distributor
     *
     * reward_unit: percent (of the document amount) | fixed (flat).
     * Config rows — editable/deletable; documents snapshot their
     * discount_amount so deleting a tier never rewrites history.
     * Filament manages the same table (ADM-02).
     */
    public function up(): void
    {
        Schema::create('acc_discount_tiers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            // commission | points | profit_balance | direct_percent
            $table->string('mode', 20);
            // qty | amount — which document total the bracket reads.
            $table->string('basis', 10);
            $table->decimal('min', 15, 2);
            $table->decimal('max', 15, 2)->nullable(); // NULL = مفتوح
            $table->decimal('reward_value', 15, 2);
            // percent (of the document amount) | fixed (flat value)
            $table->string('reward_unit', 10)->default('percent');
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(
                ['network_owner_id', 'is_active', 'mode'],
                'acc_discount_tiers_active'
            );
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_discount_tiers');
    }
};
