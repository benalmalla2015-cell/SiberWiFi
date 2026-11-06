<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Distributor/owner sales register (PLAN §2.2, Sprint ACC-06) —
     * the document row behind every `/dist/sale` posting: a cash,
     * credit, or part-paid bundle sale to a POS point.
     *
     * `total_amount`/`paid_amount` keep the document's own currency;
     * `base_*` carry the north-normalized figures the journal posts
     * (acc_balances is single-currency, same rule as ACC-05).
     *
     * payment_kind: cash | credit | partial. A credit remainder is
     * settled later through `debt_id` → acc_debts (post_entry=false —
     * the sale entry already booked the AR leg).
     *
     * `distributor_id` is the acc_agents row whose daily limits and
     * commission apply; `agent_id` is the acting account (they
     * differ when a desk clerk sells on a distributor's behalf).
     * Rows are never deleted — corrections are reversal entries.
     */
    public function up(): void
    {
        Schema::create('acc_sales', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('sale_no', 24); // SA-YYYYMMDD-NNNNNN
            $table->foreignId('pos_id')
                ->constrained('acc_pos_points')
                ->cascadeOnDelete();
            $table->foreignId('distributor_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->string('payment_kind', 10); // cash|credit|partial
            $table->decimal('total_amount', 15, 2);
            $table->decimal('paid_amount', 15, 2)->default(0);
            $table->string('currency', 10)->default('north');
            $table->decimal('exchange_rate', 18, 6)->default(1);
            $table->decimal('base_total', 15, 2);
            $table->decimal('base_paid', 15, 2)->default(0);
            $table->foreignId('cash_box_id')
                ->nullable()
                ->constrained('acc_cash_boxes')
                ->nullOnDelete();
            $table->foreignId('debt_id')
                ->nullable()
                ->constrained('acc_debts')
                ->nullOnDelete();
            $table->foreignId('journal_entry_id')
                ->nullable()
                ->constrained('acc_journal_entries')
                ->nullOnDelete();
            $table->decimal('commission_amount', 15, 2)->default(0);
            $table->string('status', 10)->default('posted'); // posted|void
            $table->timestamp('sold_at')->useCurrent();
            $table->string('note')->nullable();
            $table->string('idempotency_key')->nullable();
            $table->timestamps();

            $table->unique(['network_owner_id', 'sale_no'], 'acc_sales_no_unique');
            $table->unique('idempotency_key', 'acc_sales_idem_unique');
            $table->index(['network_owner_id', 'distributor_id', 'sold_at'], 'acc_sales_dist_date');
            $table->index(['network_owner_id', 'pos_id'], 'acc_sales_pos');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_sales');
    }
};
