<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Card-import audit trail (PLAN §2.1): bulk stock intake from a
     * CSV/Excel file AND the automatic MikroTik router-card sync —
     * `source` distinguishes 'file' uploads from 'mikrotik' batches.
     */
    public function up(): void
    {
        Schema::create('acc_card_imports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('source', 12)->default('file'); // file|mikrotik
            $table->string('filename')->nullable();
            $table->foreignId('category_id')
                ->nullable()
                ->constrained('acc_card_categories')
                ->nullOnDelete();
            $table->unsignedInteger('rows_count')->default(0);
            $table->unsignedInteger('imported_count')->default(0);
            $table->unsignedInteger('skipped_count')->default(0);
            $table->string('status', 10)->default('processed'); // processed|partial|failed
            $table->json('errors')->nullable();
            $table->foreignId('agent_id')
                ->nullable()
                ->constrained('acc_agents')
                ->nullOnDelete();
            $table->timestamps();

            $table->index(['network_owner_id', 'created_at'], 'acc_imports_owner_date');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_card_imports');
    }
};
