<?php

/**
 * ACC-06 staging fixture — a distributor account + sellable stock.
 *
 * Standalone bootstrap (uploaded to staging-app/tools/, run once by
 * deploy_acc06.py, then deleted). Idempotent via updateOrCreate —
 * safe to re-run.
 */

use App\Models\AccAgent;
use App\Models\AccCashBox;
use App\Models\AccPosPoint;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

require __DIR__ . '/../vendor/autoload.php';

$app = require __DIR__ . '/../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$owner = User::where('type', 'network_owner')->where('is_active', true)->first()
    ?? User::where('type', 'network_owner')->first();
if (! $owner) {
    echo "NO network_owner user on staging — aborting\n";
    exit(1);
}
echo "owner: #{$owner->id} {$owner->name} ({$owner->phone})\n";

// The distributor login: phone 700000011 / 123456.
$dist = User::updateOrCreate(
    ['phone' => '700000011'],
    [
        'name' => 'موزع تجريبي',
        'password' => Hash::make('123456'),
        'type' => 'client',
        'region_type' => 'north',
        'account_number' => 'SW-TEST-DIST-01',
        'referral_code' => 'TESTDIST01',
        'balance' => 0,
        'available_balance' => 0,
        'frozen_balance' => 0,
        'currency' => 'YER',
        'is_active' => true,
        'is_verified' => true,
    ]
);
echo "distributor user: #{$dist->id} {$dist->phone}\n";

$agent = AccAgent::updateOrCreate(
    ['network_owner_id' => $owner->id, 'user_id' => $dist->id],
    [
        'role' => 'distributor',
        'display_name' => 'موزع تجريبي',
        'status' => 'active',
        'cash_allowed' => true,
        'credit_allowed' => true,
        'commission_mode' => 'percent',
        'commission_value' => 5,
    ]
);
echo "agent: #{$agent->id} role=distributor commission=5%\n";

// A POS point to sell to (also usable as a collection party).
$pos = AccPosPoint::updateOrCreate(
    ['network_owner_id' => $owner->id, 'name' => 'بقالة النور'],
    [
        'status' => 'active',
        'location' => 'صنعاء',
        'phone' => '771112233',
        'points_balance' => 5000,
        'profit_balance' => 2000,
        'credit_limit' => 50000,
    ]
);
echo "pos: #{$pos->id} {$pos->name}\n";

// Sellable categories + stock so /dist/home has rows to sell.
foreach ([['باقة 1000', 1000, 600, 100], ['باقة 2000', 2000, 1100, 60]] as [$name, $sell, $cost, $qty]) {
    DB::table('acc_card_categories')->updateOrInsert(
        ['network_owner_id' => $owner->id, 'name' => $name],
        [
            'sell_price' => $sell,
            'cost_price' => $cost,
            'unit_label' => 'كرت',
            'is_active' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]
    );
    $catId = DB::table('acc_card_categories')
        ->where('network_owner_id', $owner->id)->where('name', $name)->value('id');
    DB::table('acc_stock')->updateOrInsert(
        ['network_owner_id' => $owner->id, 'category_id' => $catId],
        ['qty' => $qty, 'avg_cost' => $cost, 'created_at' => now(), 'updated_at' => now()]
    );
    echo "category: #{$catId} {$name} stock={$qty}\n";
}

// Default cash box for paid-leg posting.
$box = AccCashBox::ensureDefaultFor($owner->id, 'north');
echo "box: #{$box->id} {$box->name}\n";

echo "DONE\n";
