"""Deploy the hotspot-page template store to staging.

Uploads the renderer service + controller + routes + template assets,
then clears caches. Credentials parsed from staging_deploy.py.
Usage: py tools/deploy_pages_feature.py
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
    "app/Services/MikrotikPageRenderer.php",
    "app/Http/Controllers/Api/NetworkOwner/NetworkOwnerMikrotikPageController.php",
    "routes/api.php",
    "resources/mikrotik-pages/_shared/md5.js",
    "resources/mikrotik-pages/_shared/status.html",
    "resources/mikrotik-pages/_shared/logout.html",
]
for tpl in ("classic", "modern", "dark", "minimal", "waves"):
    FILES += [
        f"resources/mikrotik-pages/{tpl}/template.json",
        f"resources/mikrotik-pages/{tpl}/login.html",
    ]

DIRS = ["resources/mikrotik-pages/_shared"] + [
    f"resources/mikrotik-pages/{t}"
    for t in ("classic", "modern", "dark", "minimal", "waves")
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

    def run(cmd):
        print(f"$ {cmd}")
        _, out, err = client.exec_command(cmd)
        code = out.channel.recv_exit_status()
        o, e = out.read().decode(errors="replace"), err.read().decode(errors="replace")
        if o:
            print(o)
        if e:
            print(e, file=sys.stderr)
        return code, o

    try:
        sftp = client.open_sftp()
        code, out = run(f"test -f {REMOTE_APP}/artisan && echo OK")
        if "OK" not in out:
            sys.exit("staging-app/artisan not found — aborting")
        for d in DIRS:
            run(f"mkdir -p {REMOTE_APP}/{d}")
        for rel in FILES:
            local = os.path.join(BACKEND, rel.replace("/", os.sep))
            print(f"upload {rel}")
            sftp.put(local, f"{REMOTE_APP}/{rel}")
        sftp.close()
        run(f"cd {REMOTE_APP} && php artisan optimize:clear")
        run(f"cd {REMOTE_APP} && php artisan route:list --path=mikrotik")
        print("\nDone.")
    finally:
        client.close()


if __name__ == "__main__":
    main()
