<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet RADIUS event inbox (CYB-04). The engine delivers
     * auth/acct ledger records at-least-once, so (source_file,
     * source_offset) is unique and re-delivered records are skipped —
     * this is what keeps consumed_bytes accurate under retries.
     */
    public function up(): void
    {
        Schema::create('cyber_radius_events', function (Blueprint $table) {
            $table->id();
            $table->string('source_file');
            $table->unsignedBigInteger('source_offset');
            $table->string('type');
            $table->string('sim_no', 16)->nullable()->index();
            $table->string('session_id')->nullable()->index();
            $table->json('payload');
            $table->timestamp('processed_at')->nullable();
            $table->timestamps();

            $table->unique(['source_file', 'source_offset']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_radius_events');
    }
};
