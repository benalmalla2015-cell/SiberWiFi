<?php
// ACC-07 live-test seed — run once on staging via tinker include.
// Creates the demo network owner + a POS-role agent with balances,
// a package catalog with stock, ledger history, and one collection.
use Illuminate\Support\Facades\Hash;

$region = App\Models\Region::firstOrCreate(['name' => 'أمانة العاصمة'], ['type' => 'north', 'is_active' => true]);
$dir = App\Models\Directorate::firstOrCreate(['region_id' => $region->id, 'name' => 'التحرير'], ['name_en' => 'Al Tahrir', 'is_active' => true]);
$sub = App\Models\SubDirectorate::firstOrCreate(['directorate_id' => $dir->id, 'name' => 'الرباط'], ['name_en' => 'Ar Rabat', 'is_active' => true]);

$owner = App\Models\User::updateOrCreate(['phone' => '700000002'], [
    'name' => 'صاحب شبكة تجريبي', 'password' => Hash::make('123456'),
    'type' => 'network_owner', 'region_type' => 'north',
    'region_id' => $region->id, 'directorate_id' => $dir->id,
    'sub_directorate_id' => $sub->id,
    'account_number' => 'SW-TEST-OWN-001', 'referral_code' => 'TESTOWN001',
    'balance' => 0, 'available_balance' => 0, 'frozen_balance' => 0,
    'currency' => 'YER', 'is_active' => true, 'is_verified' => true,
]);
App\Models\NetworkOwner::updateOrCreate(['user_id' => $owner->id],
    ['business_name' => 'شبكة تجريبية', 'is_approved' => true]);

$posUser = App\Models\User::updateOrCreate(['phone' => '700000090'], [
    'name' => 'موظف نقطة بيع', 'password' => Hash::make('123456'),
    'type' => 'client', 'region_type' => 'north',
    'region_id' => $region->id, 'directorate_id' => $dir->id,
    'sub_directorate_id' => $sub->id,
    'account_number' => 'SW-TEST-POS-001', 'referral_code' => 'TESTPOS001',
    'balance' => 0, 'available_balance' => 0, 'frozen_balance' => 0,
    'currency' => 'YER', 'is_active' => true, 'is_verified' => true,
]);

$agent = App\Models\AccAgent::updateOrCreate(
    ['network_owner_id' => $owner->id, 'user_id' => $posUser->id],
    ['role' => 'pos', 'display_name' => 'موظف النقطة', 'phone' => '700000090',
     'status' => 'active', 'cash_allowed' => true, 'credit_allowed' => true]);

$pos = App\Models\AccPosPoint::updateOrCreate(
    ['network_owner_id' => $owner->id, 'agent_id' => $agent->id],
    ['name' => 'نقطة البيع التجريبية', 'location' => 'صنعاء - التحرير',
     'owner_name' => 'أحمد محمد', 'phone' => '700000090',
     'status' => 'active', 'credit_limit' => 0,
     'points_balance' => 10000, 'profit_balance' => 5000]);

$cats = [
    ['باقة ساعة', 100, 80, 100],
    ['باقة يوم', 500, 400, 50],
    ['باقة أسبوع', 2500, 2100, 10],
];
foreach ($cats as $i => [$nm, $sell, $cost, $qty]) {
    $cat = App\Models\AccCardCategory::updateOrCreate(
        ['network_owner_id' => $owner->id, 'name' => $nm],
        ['sell_price' => $sell, 'cost_price' => $cost, 'unit_label' => 'كرت',
         'source_binding' => 'any', 'is_active' => true, 'sort_order' => $i + 1]);
    App\Models\AccStock::updateOrCreate(
        ['network_owner_id' => $owner->id, 'category_id' => $cat->id],
        ['qty' => $qty, 'avg_cost' => $cost]);
}

$box = App\Models\AccCashBox::ensureDefaultFor($owner->id);

if (!App\Models\AccPointsLedger::where('pos_id', $pos->id)->exists()) {
    App\Models\AccPointsLedger::create([
        'network_owner_id' => $owner->id, 'pos_id' => $pos->id,
        'reason' => 'bonus', 'delta' => 10000, 'balance_after' => 10000,
        'agent_id' => $agent->id, 'note' => 'رصيد افتتاحي',
        'created_at' => now(),
    ]);
    App\Models\AccProfitLedger::create([
        'network_owner_id' => $owner->id, 'party_type' => 'pos',
        'party_id' => $pos->id, 'reason' => 'sale_commission',
        'delta' => 5000, 'agent_id' => $agent->id,
        'note' => 'عمولات مبيعات سابقة', 'created_at' => now(),
    ]);
}

if (!App\Models\AccCollection::where('party_type', 'pos')
        ->where('party_id', $pos->id)->exists()) {
    App\Models\AccCollection::create([
        'network_owner_id' => $owner->id, 'collector_agent_id' => null,
        'party_type' => 'pos', 'party_id' => $pos->id,
        'party_name' => $pos->name, 'phone' => '700000090',
        'amount' => 2000, 'currency' => 'north', 'exchange_rate' => 1,
        'base_amount' => 2000, 'cash_box_id' => $box->id,
        'collected_at' => now()->subDays(2),
        'note' => 'تحصيل تجريبي',
        'idempotency_key' => 'seed-col-' . $pos->id,
    ]);
    $box->increment('balance', 2000);
}

echo "OK owner={$owner->id} pos_user={$posUser->id} agent={$agent->id} point={$pos->id}\n";
