<?php

use App\Http\Controllers\Api\Cyber\CoverageController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| CyberNet coverage map routes — CYB-08 fragment
|--------------------------------------------------------------------------
| Loaded by routes/api_cyber.php under /api/cyber (name prefix cyber.).
|
| GET /api/cyber/coverage — public, read-only: the live CyberNet
| points the subscriber app draws on its map.
*/

Route::get('coverage', [CoverageController::class, 'index'])->name('coverage');
