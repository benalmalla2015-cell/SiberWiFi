"""Deploy Sprint 8+9 backend files to staging and run migrations.

Credentials are parsed from the existing staging_deploy.py so secrets
are not duplicated into this file. Uploads only the files Sprint 8/9
touched, then runs `php artisan migrate` inside staging-app.

Usage: py tools/deploy_mikrotik_sprints.py
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

# Parse SSH credentials from the existing deploy script (no copies).
_src = open(os.path.join(ROOT, "staging_deploy.py"), encoding="utf-8").read()
HOST = re.search(r"ssh\.connect\('([^']+)'", _src).group(1)
PORT = int(re.search(r"port=(\d+)", _src).group(1))
USER = re.search(r"username='([^']+)'", _src).group(1)
PASSWORD = re.search(r"password='([^']+)'", _src).group(1)

# local path (relative to backend/) -> remote path (relative to staging-app/)
FILES = [
    # Sprint 8 + 9 migrations
    "database/migrations/2026_10_15_000001_create_mikrotik_routers_table.php",
    "database/migrations/2026_10_15_000002_add_mikrotik_source_to_cards_table.php",
    "database/migrations/2026_10_16_000001_create_mikrotik_plans_table.php",
    "database/migrations/2026_10_16_000002_create_mikrotik_payment_requests_table.php",
    "database/migrations/2026_10_16_000003_create_mikrotik_subscriptions_table.php",
    "database/migrations/2026_10_16_000004_seed_mikrotik_subscription_settings.php",
    # Models
    "app/Models/Card.php",
    "app/Models/MikrotikRouter.php",
    "app/Models/MikrotikPlan.php",
    "app/Models/MikrotikSubscription.php",
    "app/Models/MikrotikPaymentRequest.php",
    # Controllers
    "app/Http/Controllers/Api/NetworkOwner/NetworkOwnerCardController.php",
    "app/Http/Controllers/Api/NetworkOwner/NetworkOwnerMikrotikController.php",
    "app/Http/Controllers/Api/NetworkOwner/NetworkOwnerMikrotikSubscriptionController.php",
    # Filament resources + pages
    "app/Filament/Resources/MikrotikRouterResource.php",
    "app/Filament/Resources/MikrotikRouterResource/Pages/ListMikrotikRouters.php",
    "app/Filament/Resources/MikrotikRouterResource/Pages/EditMikrotikRouter.php",
    "app/Filament/Resources/MikrotikPlanResource.php",
    "app/Filament/Resources/MikrotikPlanResource/Pages/ListMikrotikPlans.php",
    "app/Filament/Resources/MikrotikPlanResource/Pages/CreateMikrotikPlan.php",
    "app/Filament/Resources/MikrotikPlanResource/Pages/EditMikrotikPlan.php",
    "app/Filament/Resources/MikrotikSubscriptionResource.php",
    "app/Filament/Resources/MikrotikSubscriptionResource/Pages/ListMikrotikSubscriptions.php",
    "app/Filament/Resources/MikrotikSubscriptionResource/Pages/EditMikrotikSubscription.php",
    "app/Filament/Resources/MikrotikPaymentRequestResource.php",
    "app/Filament/Resources/MikrotikPaymentRequestResource/Pages/ListMikrotikPaymentRequests.php",
    "app/Filament/Resources/MikrotikPaymentRequestResource/Pages/EditMikrotikPaymentRequest.php",
    # Routes
    "routes/api.php",
]

DIRS = [
    "app/Filament/Resources/MikrotikRouterResource/Pages",
    "app/Filament/Resources/MikrotikPlanResource/Pages",
    "app/Filament/Resources/MikrotikSubscriptionResource/Pages",
    "app/Filament/Resources/MikrotikPaymentRequestResource/Pages",
]


def connect():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    for attempt in range(5):
        try:
            client.connect(HOST, port=PORT, username=USER, password=PASSWORD,
                           timeout=30, banner_timeout=120, auth_timeout=120)
            return client
        except Exception as e:  # noqa: BLE001
            print(f"SSH attempt {attempt + 1} failed: {e}", file=sys.stderr)
            time.sleep(10)
    sys.exit(1)


def run(client, cmd):
    print(f"$ {cmd}")
    _, stdout, stderr = client.exec_command(cmd)
    code = stdout.channel.recv_exit_status()
    out = stdout.read().decode(errors="replace")
    err = stderr.read().decode(errors="replace")
    if out:
        print(out)
    if err:
        print(err, file=sys.stderr)
    return code, out, err


def main():
    client = connect()
    sftp = client.open_sftp()
    try:
        # Sanity: staging app root must exist and contain artisan.
        code, out, _ = run(client, f"test -f {REMOTE_APP}/artisan && echo OK")
        if "OK" not in out:
            print("staging-app/artisan not found — aborting", file=sys.stderr)
            sys.exit(1)

        for d in DIRS:
            run(client, f"mkdir -p {REMOTE_APP}/{d}")

        for rel in FILES:
            local = os.path.join(BACKEND, rel.replace("/", os.sep))
            remote = f"{REMOTE_APP}/{rel}"
            print(f"upload {rel}")
            sftp.put(local, remote)

        # Clear caches so the new routes/models register, then migrate.
        run(client, f"cd {REMOTE_APP} && php artisan optimize:clear")
        code, out, err = run(client, f"cd {REMOTE_APP} && php artisan migrate --force")
        if code != 0:
            print("MIGRATION FAILED — see output above", file=sys.stderr)
            sys.exit(code)

        print("\n=== migrate:status (mikrotik tables) ===")
        run(client,
            f"cd {REMOTE_APP} && php artisan migrate:status | grep -i mikrotik")

        print("\n=== mikrotik routes ===")
        run(client,
            f"cd {REMOTE_APP} && php artisan route:list --path=network-owner/mikrotik")

        print("\nDone.")
    finally:
        sftp.close()
        client.close()


if __name__ == "__main__":
    main()
