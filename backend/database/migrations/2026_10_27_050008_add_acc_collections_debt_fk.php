<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Deferred FK: acc_collections.debt_id → acc_debts.id.
     *
     * acc_collections (050003) is created one migration BEFORE
     * acc_debts (050004), so the constraint could not be declared
     * inline without breaking MySQL table creation (sqlite — the
     * test driver — never enforced it). Adding it here keeps the
     * referential rule identical: a settled debt lives on its own
     * after its collections' FK is nulled.
     */
    public function up(): void
    {
        Schema::table('acc_collections', function (Blueprint $table) {
            $table->foreign('debt_id', 'acc_collections_debt_id_foreign')
                ->references('id')
                ->on('acc_debts')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('acc_collections', function (Blueprint $table) {
            $table->dropForeign('acc_collections_debt_id_foreign');
        });
    }
};
