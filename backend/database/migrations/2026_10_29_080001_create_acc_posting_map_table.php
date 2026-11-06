<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ACC-08 — platform-source → account bindings (PLAN §2.5).
     *
     * Each row maps one posting source (e.g. `card_purchase_platform`)
     * to the account codes the poster should use, stored as a JSON
     * `mapping`. Missing keys fall back to AccPostingMap::DEFAULTS, so
     * the owner only overrides what they care about.
     */
    public function up(): void
    {
        Schema::create('acc_posting_map', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('source', 40); // card_purchase_platform | …
            $table->json('mapping')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['network_owner_id', 'source'], 'acc_posting_map_owner_source');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_posting_map');
    }
};
