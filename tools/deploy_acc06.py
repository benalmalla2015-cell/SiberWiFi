"""Deploy the accounting backend (ACC-00..06) to staging + migrate + seed.

Earlier ACC sprints were never deployed (staging had no acc_ tables),
so this uploads the whole additive acc surface — every Acc* model,
service, controller, middleware, the provider + its registration, all
acc_* migrations 0100*-0600* — EXCEPT ACC-07's two migrations
(070001/070002) which belong to the in-flight POS-app track.

ACC-07 *code* files are uploaded too (the shared routes file already
references them); without their tables those endpoints simply error if
hit — registration is lazy so nothing else is affected.

Credentials are parsed from the existing staging_deploy.py so secrets
are not duplicated into this file.

Usage: py tools/deploy_acc06.py
"""
import glob
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


def rel_files():
    files = [
        "bootstrap/providers.php",
        "routes/api_accounting.php",
        "app/Providers/AccountingServiceProvider.php",
        "app/Http/Middleware/EnsureAccountingContext.php",
        "app/Http/Middleware/AuthorizeAccPermission.php",
        "tools/acc06_seed.php",
    ]
    files += glob.glob("app/Http/Controllers/Api/Accounting/Acc*.php", root_dir=BACKEND)
    files += glob.glob("app/Models/Acc*.php", root_dir=BACKEND)
    files += glob.glob("app/Services/Acc*.php", root_dir=BACKEND)
    # Migrations ACC-01..06 only: dated 2026_10_26/27 — the 2026_10_29
    # files (0800*, 1000*, 1100*, 1200*) belong to in-flight tracks.
    files += glob.glob("database/migrations/2026_10_2[67]*acc*.php", root_dir=BACKEND)
    # Normalise to forward slashes + de-dupe, keep stable order.
    return sorted({f.replace(os.sep, "/") for f in files})


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
        code, out, _ = run(client, f"test -f {REMOTE_APP}/artisan && echo OK")
        if "OK" not in out:
            print("staging-app/artisan not found — aborting", file=sys.stderr)
            sys.exit(1)

        run(client, f"mkdir -p {REMOTE_APP}/app/Http/Controllers/Api/Accounting"
                    f" {REMOTE_APP}/app/Http/Middleware"
                    f" {REMOTE_APP}/tools")

        for rel in rel_files():
            local = os.path.join(BACKEND, rel.replace("/", os.sep))
            if rel.startswith("tools/"):
                local = os.path.join(ROOT, "testapp", rel.replace("/", os.sep))
            if not os.path.exists(local):
                print(f"MISSING locally: {rel}", file=sys.stderr)
                continue
            print(f"upload {rel}")
            sftp.put(local, f"{REMOTE_APP}/{rel}")

        # Remove in-flight tracks' migrations that were uploaded by an
        # earlier glob — they must not migrate on staging yet.
        run(client, f"rm -f {REMOTE_APP}/database/migrations/2026_10_29_*acc*.php")

        # Partial tables from the earlier failed runs (CREATE applied,
        # FK ALTER failed, migration unrecorded) — drop so migrate can
        # recreate them cleanly.
        run(client, f"cd {REMOTE_APP} && php artisan tinker --execute="
                    f"\"Schema::dropIfExists('acc_collections');"
                    f"Schema::dropIfExists('acc_sales'); echo 'dropped';\"")
        run(client, f"cd {REMOTE_APP} && php artisan optimize:clear")
        run(client, f"cd {REMOTE_APP} && php artisan migrate --force")

        # Seed the distributor fixture (idempotent updateOrCreate).
        run(client, f"cd {REMOTE_APP} && php tools/acc06_seed.php")
        run(client, f"rm -f {REMOTE_APP}/tools/acc06_seed.php")
    finally:
        sftp.close()
        client.close()


if __name__ == "__main__":
    main()
