<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ACC-12 — accounting backup snapshots (PLAN §2.5).
     *
     * Each row registers one exported JSON snapshot of the tenant's
     * acc_* tables (stored under storage/app/acc_backups/{owner}/).
     * `checksum` is the sha256 of the canonical tables payload —
     * verified again on restore so a tampered/truncated file is
     * rejected before any row is touched.
     */
    public function up(): void
    {
        Schema::create('acc_backups', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('filename', 190);
            $table->unsignedBigInteger('size')->default(0);
            $table->unsignedInteger('tables_count')->default(0);
            $table->unsignedInteger('rows_count')->default(0);
            $table->string('checksum', 64);
            $table->foreignId('created_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->timestamps();

            $table->index(['network_owner_id', 'created_at'], 'acc_backups_owner_date');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_backups');
    }
};
