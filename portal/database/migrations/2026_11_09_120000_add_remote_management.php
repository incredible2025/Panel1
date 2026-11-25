<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('app_devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('managed_app_id')->constrained()->cascadeOnDelete();
            $table->string('secret_hash', 64);
            $table->string('version', 80);
            $table->unsignedInteger('build');
            $table->unsignedBigInteger('revision')->default(0);
            $table->timestamp('last_seen_at')->index();
            $table->boolean('tester')->default(false);
            $table->string('label', 80)->nullable();
            $table->string('pair_hash', 64)->nullable()->unique();
            $table->timestamp('pair_expires_at')->nullable();
            $table->unique(['managed_app_id', 'secret_hash']);
        });
        Schema::create('app_releases', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('managed_app_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('status', 24)->default('queued');
            $table->json('manifest')->nullable();
            $table->timestamps();
        });
        Schema::table('managed_apps', function (Blueprint $table) {
            $table->uuid('public_release_id')->nullable();
            $table->uuid('test_release_id')->nullable();
        });
        Schema::create('management_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('managed_app_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('action', 100);
            $table->timestamp('created_at')->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('management_events');
        Schema::table('managed_apps', function (Blueprint $table) {
            $table->dropColumn(['public_release_id', 'test_release_id']);
        });
        Schema::dropIfExists('app_releases');
        Schema::dropIfExists('app_devices');
    }
};
