<?php

use App\Http\Controllers\PublicConfigController;
use Illuminate\Support\Facades\Route;

// Stateless: periodic app checks must not create customer sessions or cookies.
Route::get('/v1/apps/{appId}/config', PublicConfigController::class)
    ->where('appId', '[a-z][a-z0-9-]{2,63}')->name('config.show');
