"""Sprint 9 follow-up: seed missing app_settings + verify wallet debit path.

Fixes found during activation:
  - mikrotik.trial_days + mikrotik.free_features rows were missing from
    app_settings (staging DB rebuild wiped them) — re-insert them.
  - Wallet subscribe path was untested (balance was 0) — top up the
    staging test owner, subscribe, verify debit + WalletLog + new sub.

Usage: py tools/sprint9_verify_wallet.py
"""
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

import paramiko

sys.stdout.reconfigure(encoding='utf-8')

ROOT = r"C:\Users\HP\Desktop\saiberwifi"
REMOTE_APP = "/home/u170359695/domains/saiberwifi.net/staging-app"
API = "https://staging.saiberwifi.net/api"

_src = open(os.path.join(ROOT, "staging_deploy.py"), encoding="utf-8").read()
HOST = re.search(r"ssh\.connect\('([^']+)'", _src).group(1)
PORT = int(re.search(r"port=(\d+)", _src).group(1))
USER = re.search(r"username='([^']+)'", _src).group(1)
PASSWORD = re.search(r"password='([^']+)'", _src).group(1)


def connect():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, port=PORT, username=USER, password=PASSWORD,
                   timeout=30, banner_timeout=120, auth_timeout=120)
    return client


def run(client, cmd):
    print(f"$ {cmd[:120]}")
    _, stdout, stderr = client.exec_command(cmd)
    code = stdout.channel.recv_exit_status()
    out = stdout.read().decode(errors="replace")
    err = stderr.read().decode(errors="replace")
    if out:
        print(out)
    if err:
        print(err, file=sys.stderr)
    return code, out, err


def tinker(client, php):
    esc = php.replace("'", "'\\''")
    return run(client,
               f"cd {REMOTE_APP} && php artisan tinker --execute='{esc}'")


def api(method, path, token=None, data=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(API + path, data=body, headers=headers,
                                 method=method)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def main():
    client = connect()

    print("=== 1) Re-seed missing app_settings ===")
    tinker(client, """
App\\Models\\AppSetting::updateOrCreate(['key'=>'mikrotik.trial_days'],
  ['value'=>'14','type'=>'integer','is_public'=>false,
   'description'=>'مدة التجربة المجانية لتطبيق إدارة المايكروتك (بالأيام)']);
App\\Models\\AppSetting::updateOrCreate(['key'=>'mikrotik.free_features'],
  ['value'=>json_encode(['mikrotik.connection','mikrotik.monitoring','mikrotik.hotspot_users']),
   'type'=>'json','is_public'=>false,
   'description'=>'الميزات المجانية لتطبيق المايكروتك بعد انتهاء التجربة']);
echo json_encode(App\\Models\\AppSetting::where('key','like','mikrotik.%')
  ->pluck('value','key')->toArray(), JSON_UNESCAPED_UNICODE);
""")

    print("\n=== 2) Top up owner 700000002 (staging test credit) ===")
    tinker(client, """
$u = App\\Models\\User::where('phone','700000002')->firstOrFail();
$u->increment('balance', 30000);
$u->increment('available_balance', 30000);
echo 'balance='.$u->fresh()->balance.' avail='.$u->fresh()->available_balance;
""")

    print("\n=== 3) Wallet subscribe → plan#2 (احترافي 12000) ===")
    c, res = api("POST", "/auth/login",
                 data={"phone": "700000002", "password": "123456"})
    tok = (res.get("data") or {}).get("token") or res.get("token")
    c, r = api("POST", "/network-owner/mikrotik/subscribe", tok,
               data={"plan_id": 2})
    print(f"[{c}]", json.dumps(r, ensure_ascii=False))

    print("\n=== 4) Verify debit + WalletLog + sub ===")
    tinker(client, """
$u = App\\Models\\User::where('phone','700000002')->first();
echo 'balance='.$u->balance.' avail='.$u->available_balance;
echo \"\\n\" . json_encode(App\\Models\\WalletLog::where('user_id',$u->id)
  ->where('reference_type','mikrotik_subscription')->latest()->first()?->toArray(),
  JSON_UNESCAPED_UNICODE);
echo \"\\n\" . json_encode(App\\Models\\MikrotikSubscription::where('user_id',$u->id)
  ->with('plan:id,name')->latest('id')->first()?->toArray(), JSON_UNESCAPED_UNICODE);
""")

    print("\n=== 5) Entitlements after wallet subscribe ===")
    c, r = api("GET", "/network-owner/mikrotik/entitlements", tok)
    print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:700])

    client.close()
    print("\nDone.")


if __name__ == "__main__":
    main()
