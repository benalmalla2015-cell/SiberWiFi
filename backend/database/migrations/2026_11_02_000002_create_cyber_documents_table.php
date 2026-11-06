<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Subscriber identity documents (CYB-03). Paths point into the
     * private `local` disk (storage/app/private) — never served publicly.
     * back_path is null for passports (single image), required for
     * national_id at the request layer.
     */
    public function up(): void
    {
        Schema::create('cyber_documents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('subscriber_id')
                ->constrained('cyber_subscribers')
                ->cascadeOnDelete();
            $table->enum('document_type', ['national_id', 'passport']);
            $table->string('front_path');
            $table->string('back_path')->nullable();
            $table->enum('review_status', ['pending', 'approved', 'rejected'])
                ->default('pending');
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamps();

            $table->index(['subscriber_id', 'review_status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_documents');
    }
};
