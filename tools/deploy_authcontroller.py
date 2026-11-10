"""Deploy AuthController.php (multi-session login fix) to staging."""
import os
import re
import sys
import time

import paramiko

ROOT = r"C:\Users\HP\Desktop\saiberwifi"
REMOTE_APP = "/home/u170359695/domains/saiberwifi.net/staging-app"
REMOTE_SUB = "app/Http/Controllers/Api/AuthController.php"

LOCAL = os.path.join(ROOT, "testapp", "backend", "app", "Http", "Controllers", "Api", "AuthController.php")

_src = open(os.path.join(ROOT, "staging_deploy.py"), encoding="utf-8").read()
HOST = re.search(r"ssh\.connect\('([^']+)'", _src).group(1)
PORT = int(re.search(r"port=(\d+)", _src).group(1))
USER = re.search(r"username='([^']+)'", _src).group(1)
PASSWORD = re.search(r"password='([^']+)'", _src).group(1)

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
for attempt in range(5):
    try:
        client.connect(HOST, port=PORT, username=USER, password=PASSWORD,
                       timeout=30, banner_timeout=120, auth_timeout=120)
        break
    except Exception as e:  # noqa: BLE001
        print(f"attempt {attempt + 1}: {e}", file=sys.stderr)
        time.sleep(10)
else:
    sys.exit(1)

sftp = client.open_sftp()
sftp.put(LOCAL, f"{REMOTE_APP}/{REMOTE_SUB}.uploaded")
sftp.close()

_, out, err = client.exec_command(
    f"mv {REMOTE_APP}/{REMOTE_SUB}.uploaded {REMOTE_APP}/{REMOTE_SUB} "
    f"&& cd {REMOTE_APP} && php artisan config:clear && php artisan cache:clear && echo DEPLOYED"
)
out.channel.recv_exit_status()
print(out.read().decode(), err.read().decode(), file=sys.stderr)
client.close()
