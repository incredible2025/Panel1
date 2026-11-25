<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('playback_events', function (Blueprint $table) {
            $table->unsignedSmallInteger('schema_version')->default(1);
            $table->uuid('session_id')->nullable();
            $table->unsignedInteger('sequence')->nullable();
            $table->unsignedInteger('elapsed_ms')->nullable();
            $table->timestamp('occurred_at')->nullable();
            $table->json('details')->nullable();
            $table->index(['app_device_id', 'session_id']);
            $table->unique(['app_device_id', 'session_id', 'sequence'], 'playback_session_sequence');
        });
    }

    public function down(): void
    {
        Schema::table('playback_events', function (Blueprint $table) {
            $table->dropUnique('playback_session_sequence');
            $table->dropIndex(['app_device_id', 'session_id']);
            $table->dropColumn(['schema_version', 'session_id', 'sequence', 'elapsed_ms', 'occurred_at', 'details']);
        });
    }
};
