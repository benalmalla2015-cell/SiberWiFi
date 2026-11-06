<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Cash collections (PLAN §2.3) — money received from a party:
     * a POS point settling its receivable, a distributor remitting,
     * or a customer/person paying by name+phone.
     *
     * `amount`/`currency`/`exchange_rate` keep the document's own
     * currency; `base_amount` is the north-normalized value the
     * journal posts (acc_balances is single-currency). `debt_id`
     * links a collection that settled an acc_debts row.
     */
    public function up(): void
    {
        Schema::create('acc_collections', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignId('collector_agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            // pos | distributor | customer | person
            $table->string('party_type', 20);
            $table->unsignedBigInteger('party_id')->nullable();
            $table->string('party_name');
            $table->string('phone', 30)->nullable();
            $table->decimal('amount', 15, 2);
            $table->string('currency', 10)->default('north');
            $table->decimal('exchange_rate', 18, 6)->default(1);
            $table->decimal('base_amount', 15, 2);
            $table->foreignId('cash_box_id')
                ->constrained('acc_cash_boxes')
                ->cascadeOnDelete();
            // FK added by 050008 — acc_debts (050004) does not exist
            // yet when this table is created; an inline constraint
            // breaks on MySQL (sqlite never enforced it in tests).
            $table->unsignedBigInteger('debt_id')->nullable()->index();
            $table->foreignId('journal_entry_id')
                ->nullable()
                ->constrained('acc_journal_entries')
                ->nullOnDelete();
            $table->timestamp('collected_at')->useCurrent();
            $table->string('note')->nullable();
            $table->string('idempotency_key')->nullable();
            $table->timestamps();

            $table->unique('idempotency_key', 'acc_collections_idem_unique');
            $table->index(['network_owner_id', 'party_type', 'party_id'], 'acc_collections_party');
            $table->index(['network_owner_id', 'collected_at'], 'acc_collections_date');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_collections');
    }
};
