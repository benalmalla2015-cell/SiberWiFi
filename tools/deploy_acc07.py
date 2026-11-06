"""Deploy the accounting module (ACC-00..07) to staging + seed POS demo data.

Staging had zero accounting files, so this ships the whole isolated
`acc_*` surface (models / services / controllers / middleware /
provider / routes / migrations), registers the provider, migrates,
and seeds a POS-role demo account for the ADB live run.

Credentials are parsed from staging_deploy.py so secrets are not
duplicated. Usage: py testapp/tools/deploy_acc07.py
"""
import glob
import os
import re
import sys

import paramiko

sys.stdout.reconfigure(encoding='utf-8')

ROOT = r"C:\Users\HP\Desktop\saiberwifi"
BACKEND = os.path.join(ROOT, "testapp", "backend")
REMOTE_APP = "/home/u170359695/domains/saiberwifi.net/staging-app"

_src = open(os.path.join(ROOT, "staging_deploy.py"), encoding="utf-8").read()
HOST = re.search(r"ssh\.connect\('([^']+)'", _src).group(1)
PORT = int(re.search(r"port=(\d+)", _src).group(1))
USER = re.search(r"username='([^']+)'", _src).group(1)
PASSWORD = re.search(r"password='([^']+)'", _src).group(1)


def rel(pattern):
    base = os.path.join(BACKEND, pattern)
    return sorted(
        os.path.relpath(p, BACKEND).replace("\\", "/")
        for p in glob.glob(base)
    )


FILES = (
    ["bootstrap/providers.php",
     "app/Providers/AccountingServiceProvider.php",
     "routes/api_accounting.php",
     "app/Http/Middleware/EnsureAccountingContext.php",
     "app/Http/Middleware/AuthorizeAccPermission.php"]
    + rel("app/Models/Acc*.php")
    + rel("app/Services/Acc*.php")
    + rel("app/Http/Controllers/Api/Accounting/*.php")
    + rel("database/migrations/*acc*.php")
)

SEED_PHP = r"""
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
    'type' => 'customer', 'region_type' => 'north',
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
"""


def run(ssh, cmd, timeout=300):
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode(errors="ignore")
    err = stderr.read().decode(errors="ignore")
    code = stdout.channel.recv_exit_status()
    return code, out, err


def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, port=PORT, username=USER, password=PASSWORD,
                timeout=30, banner_timeout=120, auth_timeout=120)

    sftp = ssh.open_sftp()

    def mkdir_p(path):
        parts = path.strip("/").split("/")
        cur = ""
        for p in parts:
            cur += "/" + p
            try:
                sftp.mkdir(cur)
            except IOError:
                pass

    print(f"uploading {len(FILES)} files...")
    for f in FILES:
        local = os.path.join(BACKEND, f.replace("/", os.sep))
        remote = f"{REMOTE_APP}/{f}"
        mkdir_p(os.path.dirname(remote))
        sftp.put(local, remote)
    print("uploads done")

    # tinker seed file
    seed_remote = f"{REMOTE_APP}/acc_seed_tmp.php"
    with sftp.file(seed_remote, "w") as fh:
        fh.write("<?php\n" + SEED_PHP)
    sftp.close()

    for label, cmd in [
        ("composer dump-autoload", f"cd {REMOTE_APP} && composer dump-autoload -o 2>&1 | tail -3"),
        ("pending migrations", f"cd {REMOTE_APP} && php artisan migrate:status 2>/dev/null | grep -i Pending | head -40"),
        ("migrate", f"cd {REMOTE_APP} && php artisan migrate --force 2>&1 | tail -50"),
        ("optimize clear", f"cd {REMOTE_APP} && php artisan optimize:clear 2>&1 | tail -8"),
        ("seed", f"cd {REMOTE_APP} && php artisan tinker --execute=\"include base_path('acc_seed_tmp.php');\" 2>&1 | tail -15"),
        ("routes check", f"cd {REMOTE_APP} && php artisan route:list --path=accounting 2>&1 | grep -c ."),
    ]:
        code, out, err = run(ssh, cmd)
        print(f"\n=== {label} (exit {code}) ===\n{out.strip()}")
        if err.strip() and 'deprecat' not in err.lower():
            print(f"STDERR: {err.strip()[:1500]}")

    run(ssh, f"rm -f {REMOTE_APP}/acc_seed_tmp.php")
    ssh.close()


if __name__ == "__main__":
    main()
