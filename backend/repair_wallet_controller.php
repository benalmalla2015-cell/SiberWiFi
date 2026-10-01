<?php
$path = __DIR__ . '/app/Http/Controllers/Api/WalletController.php';
$content = file_get_contents($path);
$marker = "use Illuminate\\Http\\JsonResponse;";
$offset = strpos($content, $marker);
if ($offset === false) {
    throw new RuntimeException('Valid controller marker not found');
}
$body = substr($content, $offset);
$header = <<<'PHP'
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BankAccount;
use App\Models\ChargingPoint;
use App\Models\User;
use App\Models\WalletLog;
use App\Services\NotificationService;
PHP;
copy($path, $path . '.corrupt-20260905');
file_put_contents($path, $header . "\n" . $body);
echo "WalletController restored\n";
