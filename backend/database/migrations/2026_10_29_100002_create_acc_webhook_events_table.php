<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Event notification templates (PLAN §2.5, Sprint ACC-10).
     *
     * Each row maps an accounting event to a WhatsApp message
     * template with {placeholders} — rendered server-side by
     * AccWebhookService at write time and returned to the app as a
     * wa.me deep link + in-app push to the bound party's user.
     *
     * Events (free-form, validated at the model layer):
     *   sale.created | sale.updated | sale.deleted
     *   collection.created | debt.due
     *
     * Templates are config rows — toggled via is_active; every
     * dispatch is audit-logged, nothing is sent silently.
     */
    public function up(): void
    {
        Schema::create('acc_webhook_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('network_owner_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('event', 40);
            $table->string('channel', 20)->default('whatsapp');
            $table->text('template_body');
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(
                ['network_owner_id', 'event', 'is_active'],
                'acc_webhook_events_lookup'
            );
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('acc_webhook_events');
    }
};
