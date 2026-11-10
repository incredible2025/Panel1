<?php

use App\Http\Controllers\BrandWizardController;
use App\Http\Controllers\DashboardOperationsController;
use App\Http\Controllers\ManagementController;
use App\Http\Controllers\OwnerSetupController;
use App\Http\Controllers\RemoteManagementController;
use App\Http\Middleware\RequireTwoFactor;
use Illuminate\Support\Facades\Route;

Route::redirect('/', '/dashboard')->name('home');
Route::get('/owner-setup/{token}', [OwnerSetupController::class, 'show'])->where('token', '[a-f0-9]{64}')->middleware('throttle:10,1')->name('owner.setup');
Route::post('/owner-setup/{token}', [OwnerSetupController::class, 'store'])->where('token', '[a-f0-9]{64}')->middleware('throttle:5,1')->name('owner.setup.store');

Route::middleware(['auth', 'verified', RequireTwoFactor::class])->group(function () {
    Route::get('/dashboard', [ManagementController::class, 'index'])->name('dashboard');
    Route::get('/health', [DashboardOperationsController::class, 'health'])->name('operations.health');
    Route::get('/bulk', [DashboardOperationsController::class, 'bulk'])->name('operations.bulk');
    Route::post('/bulk/review', [DashboardOperationsController::class, 'prepareBulk'])->name('operations.bulk.prepare');
    Route::get('/reviews/{ticket}', [DashboardOperationsController::class, 'review'])->name('operations.review');
    Route::post('/reviews/{ticket}', [DashboardOperationsController::class, 'confirm'])->block(10, 10)->name('operations.confirm');
    Route::get('/apps/new', [BrandWizardController::class, 'start'])->name('brands.start');
    Route::post('/apps/new/review', [BrandWizardController::class, 'prepare'])->name('brands.prepare');
    Route::get('/brand-reviews/{ticket}', [BrandWizardController::class, 'review'])->name('brands.review');
    Route::get('/brand-reviews/{ticket}/logo', [BrandWizardController::class, 'previewLogo'])->name('brands.logo');
    Route::post('/brand-reviews/{ticket}', [BrandWizardController::class, 'create'])->block(10, 10)->name('brands.create');
    Route::post('/apps/{managedApp}/reseller', [DashboardOperationsController::class, 'reseller'])->name('operations.reseller');
    Route::post('/apps/{managedApp}/artwork', [BrandWizardController::class, 'uploadLogo'])->name('brands.artwork');
    Route::get('/apps/{managedApp}/branding', [BrandWizardController::class, 'kit'])->name('brands.kit');
    Route::post('/apps/{managedApp}/releases/{release}/result', [DashboardOperationsController::class, 'result'])->name('releases.result');
    Route::get('/activity', [RemoteManagementController::class, 'metrics'])->name('activity.metrics');
    Route::get('/events', [RemoteManagementController::class, 'events'])->name('management.events');
    Route::post('/apps/{managedApp}/uploads', [RemoteManagementController::class, 'upload'])->middleware('throttle:20,1')->name('releases.upload');
    Route::post('/apps/{managedApp}/releases/{release}', [RemoteManagementController::class, 'release'])->name('releases.action');
    Route::post('/apps/{managedApp}/pair', [RemoteManagementController::class, 'pair'])->middleware('throttle:10,1')->name('devices.pair');
    Route::post('/apps/{managedApp}/devices/{device}/revoke', [RemoteManagementController::class, 'revoke'])->name('devices.revoke');
    Route::post('/apps', [ManagementController::class, 'create'])->name('apps.create');
    Route::get('/apps/{managedApp}', [ManagementController::class, 'show'])->name('apps.show');
    Route::post('/apps/{managedApp}/draft', [ManagementController::class, 'save'])->name('apps.save');
    Route::post('/apps/{managedApp}/publish', [ManagementController::class, 'publish'])->name('apps.publish');
    Route::post('/apps/{managedApp}/rollback/{revision}', [ManagementController::class, 'rollback'])->whereNumber('revision')->name('apps.rollback');
    Route::get('/apps/{managedApp}/profile', [ManagementController::class, 'profile'])->name('apps.profile');
    Route::post('/apps/{managedApp}/replace', [ManagementController::class, 'replace'])->middleware('password.confirm')->name('apps.replace');
    Route::get('/staff', [ManagementController::class, 'staff'])->name('staff.index');
    Route::post('/staff', [ManagementController::class, 'addStaff'])->middleware('password.confirm')->name('staff.create');
    Route::post('/staff/{user}/toggle', [ManagementController::class, 'toggleStaff'])->middleware('password.confirm')->name('staff.toggle');
});

require __DIR__.'/settings.php';
