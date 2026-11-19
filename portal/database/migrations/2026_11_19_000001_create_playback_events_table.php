<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('playback_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('managed_app_id')->constrained()->cascadeOnDelete();
            $table->foreignId('app_device_id')->constrained()->cascadeOnDelete();
            $table->uuid('event_id');
            $table->string('version', 80);
            $table->unsignedInteger('build');
            $table->string('device_model', 80);
            $table->string('os_version', 40);
            $table->string('form_factor', 12);
            $table->string('engine', 16);
            $table->string('decoding', 16);
            $table->string('kind', 12);
            $table->string('category', 32);
            $table->string('source', 12);
            $table->timestamp('created_at');
            $table->unique(['app_device_id', 'event_id']);
            $table->index(['managed_app_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('playback_events');
    }
};
