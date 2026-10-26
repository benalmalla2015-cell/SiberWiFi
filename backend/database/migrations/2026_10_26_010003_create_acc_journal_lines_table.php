<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Journal lines — every entry must balance: Σdebit = Σcredit.
     * party_* links the line to a business party for acc_balances.
     */
    public function up(): void
    {
        Schema::create('acc_journal_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('entry_id')
                ->constrained('acc_journal_entries')
                ->cascadeOnDelete();
            $table->string('account_code', 20);
            // owner | pos | distributor | customer | supplier | box
            $table->string('party_type', 20)->nullable();
            $table->unsignedBigInteger('party_id')->nullable();
            $table->decimal('debit', 18, 2)->default(0);
            $table->decimal('credit', 18, 2)->default(0);
            $table->timestamps();

            $table->index(['entry_id', 'account_code']);
            $table->index(['party_type', 'party_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_journal_lines');
    }
};
