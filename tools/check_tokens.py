"""Inspect sanctum tokens for the staging test owner — who created them and when."""
import base64
import os
import re
import sys

import paramiko

sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"C:\Users\HP\Desktop\saiberwifi"
REMOTE = "/home/u170359695/domains/saiberwifi.net/staging-app"

_src = open(os.path.join(ROOT, "staging_deploy.py"), encoding="utf-8").read()
HOST = re.search(r"ssh\.connect\('([^']+)'", _src).group(1)
PORT = int(re.search(r"port=(\d+)", _src).group(1))
USER = re.search(r"username='([^']+)'", _src).group(1)
PASSWORD = re.search(r"password='([^']+)'", _src).group(1)

PHP = """
$u = \\App\\Models\\User::where('phone','700000099')->first();
echo 'uid='.$u->id.PHP_EOL;
foreach (\\App\\Models\\MikrotikSubscription::where('user_id',$u->id)->get() as $s) {
    echo 'sub '.$s->id.' plan='.$s->plan_id.' status='.$s->status.' ends='.$s->ends_at.PHP_EOL;
}
echo 'enforce='.\\App\\Models\\AppSetting::getValue('mikrotik.enforce','?').PHP_EOL;
echo 'trial='.\\App\\Models\\AppSetting::getValue('mikrotik.trial_days','?').PHP_EOL;
echo 'free='.\\App\\Models\\AppSetting::getValue('mikrotik.free_features','?').PHP_EOL;
"""

b64 = base64.b64encode(PHP.encode()).decode()
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=30)
_, o, e = c.exec_command(f"cd {REMOTE} && echo {b64} | base64 -d | php artisan tinker", timeout=90)
print(o.read().decode())
err = e.read().decode().strip()
if err:
    print("ERR:", err[:800])
c.close()
