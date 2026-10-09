<?php

use App\Http\Controllers\Web\AccountDeletionController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::view('/privacy', 'legal.privacy')->name('privacy');
Route::redirect('/privacy-policy', '/privacy');
Route::view('/terms', 'legal.terms')->name('terms');
Route::redirect('/terms-of-service', '/terms');

Route::get('/delete-account', [AccountDeletionController::class, 'show'])->name('delete-account');
Route::post('/delete-account', [AccountDeletionController::class, 'submit'])->name('delete-account.submit');
