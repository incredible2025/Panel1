<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('playback_events', function (Blueprint $table) {
            $table->text('line_username')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('playback_events', function (Blueprint $table) {
            $table->dropColumn('line_username');
        });
    }
};
