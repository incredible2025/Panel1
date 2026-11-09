<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('role')->default('staff');
            $table->boolean('active')->default(true);
        });
        Schema::create('managed_apps', function (Blueprint $table) {
            $table->id();
            $table->string('app_id')->unique();
            $table->string('package_id')->unique();
            $table->string('name');
            $table->uuid('service_id');
            $table->json('draft');
            $table->unsignedBigInteger('revision')->default(0);
            $table->unsignedBigInteger('draft_version')->default(1);
            $table->timestamps();
        });
        Schema::create('config_revisions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('managed_app_id')->constrained()->restrictOnDelete();
            $table->unsignedBigInteger('revision');
            $table->uuid('service_id');
            $table->json('configuration');
            $table->text('payload');
            $table->text('signature');
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->string('action');
            $table->timestamp('created_at');
            $table->unique(['managed_app_id', 'revision']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('config_revisions');
        Schema::dropIfExists('managed_apps');
        Schema::table('users', fn (Blueprint $table) => $table->dropColumn(['role', 'active']));
    }
};
