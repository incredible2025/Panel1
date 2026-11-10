<?php

use App\Http\Controllers\DeviceActivityController;
use App\Http\Controllers\PublicConfigController;
use Illuminate\Support\Facades\Route;

// Stateless: periodic app checks must not create customer sessions or cookies.
Route::get('/v1/apps/{appId}/config', PublicConfigController::class)
    ->where('appId', '[a-z][a-z0-9-]{2,63}')->name('config.show');

Route::prefix('/v1/apps/{appId}')->where(['appId' => '[a-z][a-z0-9-]{2,63}'])->group(function () {
    Route::post('/activity', [DeviceActivityController::class, 'heartbeat'])->middleware('throttle:600,1');
    Route::post('/pair', [DeviceActivityController::class, 'pair'])->middleware('throttle:60,1');
    Route::get('/updates', [DeviceActivityController::class, 'updates'])->middleware('throttle:600,1')->name('device.updates');
});
