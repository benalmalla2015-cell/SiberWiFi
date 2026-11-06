<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CyberNet subscribers (CYB-03, PLAN §4.1) — the digital "SIM" holder.
     * sim_no (74XXXXXXX) is the subscriber's permanent public identity;
     * the unique index is the atomic reservation guard for concurrent
     * registrations. Geography links are read-only references to the
     * existing directorates/sub_directorates lookups (محافظة/مديرية).
     */
    public function up(): void
    {
        Schema::create('cyber_subscribers', function (Blueprint $table) {
            $table->id();
            $table->string('sim_no', 9)->unique();
            $table->string('full_name');
            $table->foreignId('directorate_id')
                ->constrained('directorates')
                ->restrictOnDelete();
            $table->foreignId('sub_directorate_id')
                ->constrained('sub_directorates')
                ->restrictOnDelete();
            $table->enum('status', ['pending', 'active', 'suspended', 'rejected'])
                ->default('pending');
            $table->timestamps();

            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cyber_subscribers');
    }
};
