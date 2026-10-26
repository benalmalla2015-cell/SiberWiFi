<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Journal entries — the immutable heart of the document cycle.
     * Entries are never updated/deleted; mistakes are fixed by a
     * reversal entry (reversal_of_id). Purely additive (PLAN §2.3).
     */
    public function up(): void
    {
        Schema::create('acc_journal_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            // JE-YYYYMMDD-NNNNN — sequential per owner per day.
            $table->string('entry_no', 32);
            $table->string('doc_type', 40);
            $table->unsignedBigInteger('doc_ref_id')->nullable();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->date('date');
            $table->string('currency', 10)->default('YER');
            $table->decimal('exchange_rate', 18, 6)->default(1);
            $table->string('memo')->nullable();
            $table->string('idempotency_key')->nullable();
            $table->foreignId('reversal_of_id')
                ->nullable()
                ->constrained('acc_journal_entries')
                ->nullOnDelete();
            $table->boolean('is_posted')->default(true);
            $table->timestamp('posted_at')->nullable();
            $table->timestamps();

            $table->unique(['network_owner_id', 'entry_no']);
            $table->unique('idempotency_key');
            $table->index(['network_owner_id', 'doc_type', 'date']);
            $table->index(['network_owner_id', 'date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_journal_entries');
    }
};
