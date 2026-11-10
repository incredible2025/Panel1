<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('managed_apps', function (Blueprint $table) {
            $table->string('reseller_name', 100)->nullable();
            $table->string('reseller_email', 180)->nullable();
            $table->string('reseller_contact', 240)->nullable();
            $table->string('downloader_code', 20)->nullable();
            $table->json('brand_spec')->nullable();
            $table->string('brand_logo')->nullable();
        });
        Schema::table('app_releases', function (Blueprint $table) {
            $table->string('test_result', 24)->default('unrecorded');
            $table->string('test_note', 240)->nullable();
            $table->foreignId('tested_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('tested_at')->nullable();
            $table->unsignedInteger('review_version')->default(1);
        });
    }

    public function down(): void
    {
        Schema::table('app_releases', function (Blueprint $table) {
            $table->dropForeign(['tested_by']);
            $table->dropColumn(['test_result', 'test_note', 'tested_by', 'tested_at', 'review_version']);
        });
        Schema::table('managed_apps', function (Blueprint $table) {
            $table->dropColumn(['reseller_name', 'reseller_email', 'reseller_contact', 'downloader_code', 'brand_spec', 'brand_logo']);
        });
    }
};
