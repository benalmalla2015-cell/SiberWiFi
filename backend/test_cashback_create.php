<?php

require_once __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

use App\Models\CashbackSetting;

try {
    $setting = CashbackSetting::create([
        'name' => 'Test Cashback',
        'min_amount' => 100,
        'cashback_percent' => 5,
        'is_active' => true,
    ]);
    echo "Created cashback setting ID: " . $setting->id . "\n";
    // clean up
    $setting->delete();
    echo "Deleted test cashback setting.\n";
} catch (Throwable $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
}
