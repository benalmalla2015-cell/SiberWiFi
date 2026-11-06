"""Deploy the admin-panel gap-fill to staging.

Uploads the feature-override migration, updated models/controllers,
the new accounting Filament resources and the mikrotik resource
updates — then php -l's every PHP file, runs the migration and
clears caches. Credentials parsed from staging_deploy.py.
Usage: py tools/deploy_admin_gapfill.py
"""
import os
import re
import sys
import time

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

FILES = [
    # Missing acc-billing schema — never deployed to staging.
    "database/migrations/2026_10_29_110001_create_acc_plans_table.php",
    "database/migrations/2026_10_29_110002_create_acc_payment_requests_table.php",
    "database/migrations/2026_10_29_110003_create_acc_subscriptions_table.php",
    "database/migrations/2026_10_29_110004_seed_acc_subscription_settings.php",
    "database/migrations/2026_11_04_000012_add_feature_overrides_to_subscriptions.php",
    "app/Models/MikrotikSubscription.php",
    "app/Models/AccSubscription.php",
    "app/Http/Controllers/Api/NetworkOwner/NetworkOwnerMikrotikSubscriptionController.php",
    "app/Http/Controllers/Api/Accounting/AccBillingController.php",
    "app/Filament/Resources/MikrotikSubscriptionResource.php",
    "app/Filament/Resources/MikrotikSubscriptionResource/Pages/CreateMikrotikSubscription.php",
    "app/Filament/Resources/MikrotikSubscriptionResource/Pages/ListMikrotikSubscriptions.php",
    "app/Filament/Resources/MikrotikPaymentRequestResource.php",
    "app/Filament/Resources/AccPlanResource.php",
    "app/Filament/Resources/AccPlanResource/Pages/ListAccPlans.php",
    "app/Filament/Resources/AccPlanResource/Pages/CreateAccPlan.php",
    "app/Filament/Resources/AccPlanResource/Pages/EditAccPlan.php",
    "app/Filament/Resources/AccSubscriptionResource.php",
    "app/Filament/Resources/AccSubscriptionResource/Pages/ListAccSubscriptions.php",
    "app/Filament/Resources/AccSubscriptionResource/Pages/CreateAccSubscription.php",
    "app/Filament/Resources/AccSubscriptionResource/Pages/EditAccSubscription.php",
    "app/Filament/Resources/AccPaymentRequestResource.php",
    "app/Filament/Resources/AccPaymentRequestResource/Pages/ListAccPaymentRequests.php",
    "app/Filament/Resources/AccPaymentRequestResource/Pages/EditAccPaymentRequest.php",
]

DIRS = [
    "app/Filament/Resources/MikrotikSubscriptionResource/Pages",
    "app/Filament/Resources/AccPlanResource/Pages",
    "app/Filament/Resources/AccSubscriptionResource/Pages",
    "app/Filament/Resources/AccPaymentRequestResource/Pages",
]


def main():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    for attempt in range(5):
        try:
            client.connect(HOST, port=PORT, username=USER, password=PASSWORD,
                           timeout=30, banner_timeout=120, auth_timeout=120)
            break
        except Exception as e:  # noqa: BLE001
            print(f"SSH attempt {attempt + 1} failed: {e}", file=sys.stderr)
            time.sleep(10)
    else:
        sys.exit(1)

    def run(cmd, check=True):
        print(f"$ {cmd}")
        _, out, err = client.exec_command(cmd)
        code = out.channel.recv_exit_status()
        o, e = out.read().decode(errors="replace"), err.read().decode(errors="replace")
        if o:
            print(o)
        if e:
            print(e, file=sys.stderr)
        if check and code != 0:
            raise SystemExit(f"command failed ({code}): {cmd}")
        return code, o

    try:
        sftp = client.open_sftp()
        run(f"test -f {REMOTE_APP}/artisan && echo OK")
        for d in DIRS:
            run(f"mkdir -p {REMOTE_APP}/{d}")
        for rel in FILES:
            local = os.path.join(BACKEND, rel.replace("/", os.sep))
            print(f"upload {rel}")
            sftp.put(local, f"{REMOTE_APP}/{rel}")
        sftp.close()

        # Syntax-check every uploaded file before touching caches —
        # a parse error must surface here, not at runtime.
        for rel in FILES:
            code, out = run(f"php -l {REMOTE_APP}/{rel}", check=False)
            if code != 0:
                raise SystemExit(f"SYNTAX ERROR in {rel} — aborting deploy")

        run(f"cd {REMOTE_APP} && php artisan migrate --force")
        run(f"cd {REMOTE_APP} && php artisan optimize:clear")
        run(f"cd {REMOTE_APP} && php artisan route:list --path=admin/mikrotik | head -20")
        run(f"cd {REMOTE_APP} && php artisan route:list --path=admin/acc | head -20")
        print("\nDone.")
    finally:
        client.close()


if __name__ == "__main__":
    main()
