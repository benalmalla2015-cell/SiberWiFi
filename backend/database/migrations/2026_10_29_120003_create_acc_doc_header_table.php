<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ACC-12 — printed-document header customization (PLAN §2.5).
     *
     * One row per tenant: the name/texts/logo flag stamped on top of
     * every printed accounting document (collection sheets, journal
     * printouts, reports). The logo image itself lives under
     * storage/app/acc_doc_logos/{owner}/ and is streamed through
     * GET /doc-header/logo — no public symlink required.
     */
    public function up(): void
    {
        Schema::create('acc_doc_header', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('business_name', 190)->nullable();
            $table->string('subtitle', 190)->nullable();
            $table->string('phone', 40)->nullable();
            $table->string('address', 190)->nullable();
            $table->string('footer_text', 190)->nullable();
            $table->boolean('show_logo')->default(true);
            $table->string('logo_path', 190)->nullable();
            $table->timestamps();

            $table->unique('network_owner_id', 'acc_doc_header_owner');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_doc_header');
    }
};
