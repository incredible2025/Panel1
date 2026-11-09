<?php

use App\Http\Controllers\ManagementController;
use App\Http\Controllers\OwnerSetupController;
use App\Http\Middleware\RequireTwoFactor;
use Illuminate\Support\Facades\Route;

Route::redirect('/', '/dashboard')->name('home');
Route::get('/owner-setup/{token}', [OwnerSetupController::class, 'show'])->where('token', '[a-f0-9]{64}')->middleware('throttle:10,1')->name('owner.setup');
Route::post('/owner-setup/{token}', [OwnerSetupController::class, 'store'])->where('token', '[a-f0-9]{64}')->middleware('throttle:5,1')->name('owner.setup.store');

Route::middleware(['auth', 'verified', RequireTwoFactor::class])->group(function () {
    Route::get('/dashboard', [ManagementController::class, 'index'])->name('dashboard');
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
