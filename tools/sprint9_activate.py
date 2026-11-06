"""Sprint 9 activation + live verification on staging.

Flow (staging only — production is never touched):
  1. SSH: inspect mikrotik_plans / app_settings / owner balances & subs
  2. API: login owner 700000002 → entitlements → plans → wallet subscribe
          → entitlements (expect active)
  3. API: login owner 778257546 → POST /mikrotik/payments (multipart receipt)
          → SSH: approve via the same atomic logic as the Filament action
          → API: entitlements (expect active)
  4. SSH: flip mikrotik.enforce=1 → API: entitlements shows enforce=true
          + a no-subscription owner gets only free features
  5. SSH: final state dump

Credentials parsed from staging_deploy.py — nothing duplicated.
Usage: py tools/sprint9_activate.py
"""
import io
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


# ── SSH helpers ──────────────────────────────────────────────────
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


def run(client, cmd, show=True):
    if show:
        print(f"$ {cmd}")
    _, stdout, stderr = client.exec_command(cmd)
    code = stdout.channel.recv_exit_status()
    out = stdout.read().decode(errors="replace")
    err = stderr.read().decode(errors="replace")
    if show and out:
        print(out)
    if show and err:
        print(err, file=sys.stderr)
    return code, out, err


def tinker(client, php):
    """Run `php artisan tinker --execute=...` on staging-app."""
    esc = php.replace("'", "'\\''")
    return run(client,
               f"cd {REMOTE_APP} && php artisan tinker --execute='{esc}'")


# ── API helpers ──────────────────────────────────────────────────
def api(method, path, token=None, data=None, files=None):
    """Minimal JSON/multipart client for the staging API."""
    url = API + path
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None
    if files is not None:
        # multipart/form-data
        boundary = "----sbr" + os.urandom(6).hex()
        buf = io.BytesIO()
        for k, v in (data or {}).items():
            buf.write(f"--{boundary}\r\n".encode())
            buf.write(
                f'Content-Disposition: form-data; name="{k}"\r\n\r\n'.encode())
            buf.write(f"{v}\r\n".encode())
        for k, (fname, fbytes, ctype) in files.items():
            buf.write(f"--{boundary}\r\n".encode())
            buf.write(
                f'Content-Disposition: form-data; name="{k}"; '
                f'filename="{fname}"\r\n'.encode())
            buf.write(f"Content-Type: {ctype}\r\n\r\n".encode())
            buf.write(fbytes)
            buf.write(b"\r\n")
        buf.write(f"--{boundary}--\r\n".encode())
        body = buf.getvalue()
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=body, headers=headers,
                                 method=method)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:  # noqa: BLE001
            return e.code, {"raw": "<non-json body>"}


def login(phone, password="123456"):
    code, res = api("POST", "/auth/login",
                    data={"phone": phone, "password": password})
    if code != 200 or not res.get("success", True):
        print(f"LOGIN {phone} FAILED [{code}]: {res}")
        sys.exit(1)
    token = (res.get("data") or {}).get("token") or res.get("token")
    print(f"login {phone} → token …{token[-8:]}")
    return token


def section(title):
    print("\n" + "=" * 60 + f"\n{title}\n" + "=" * 60)


def main():
    client = connect()

    section("1) Staging state — plans, settings, owners")
    tinker(client,
           "echo json_encode(App\\Models\\MikrotikPlan::all("
           "['id','name','price','currency','duration_days','is_active','features'])"
           "->toArray(), JSON_UNESCAPED_UNICODE);")
    tinker(client,
           "echo json_encode(App\\Models\\AppSetting::where('key','like','mikrotik.%')"
           "->pluck('value','key')->toArray(), JSON_UNESCAPED_UNICODE);")
    tinker(client,
           "echo json_encode(App\\Models\\User::whereIn('phone',['700000002','778257546'])"
           "->get(['id','phone','type','balance','available_balance'])"
           "->toArray(), JSON_UNESCAPED_UNICODE);")
    tinker(client,
           "echo json_encode(App\\Models\\MikrotikSubscription::with('plan:id,name')"
           "->get(['id','user_id','plan_id','status','ends_at'])"
           "->toArray(), JSON_UNESCAPED_UNICODE);")

    section("2) Owner 700000002 — wallet subscribe path")
    tok_a = login("700000002")
    print("\n-- entitlements (before)")
    c, r = api("GET", "/network-owner/mikrotik/entitlements", tok_a)
    print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:800])
    print("\n-- plans")
    c, r = api("GET", "/network-owner/mikrotik/plans", tok_a)
    print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:800])
    plans = r.get("data") or []
    if not plans:
        print("NO PLANS — cannot subscribe. Create one first.")
        sys.exit(1)
    plan = min(plans, key=lambda p: p["price"])
    print(f"\n-- subscribe plan#{plan['id']} «{plan['name']}» price={plan['price']}")
    c, r = api("POST", "/network-owner/mikrotik/subscribe", tok_a,
               data={"plan_id": plan["id"]})
    print(f"[{c}]", json.dumps(r, ensure_ascii=False))
    print("\n-- entitlements (after)")
    c, r = api("GET", "/network-owner/mikrotik/entitlements", tok_a)
    print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:800])

    section("3) Owner 778257546 — manual transfer path")
    tok_b = login("778257546")
    # 1x1 px PNG receipt
    png = bytes.fromhex(
        "89504e470d0a1a0a0000000d494844520000000100000001080600000"
        "01f15c4890000000d49444154789c626001000000ffff03000006000"
        "557bfabd40000000049454e44ae426082")
    print("\n-- POST payments (receipt attached)")
    c, r = api("POST", "/network-owner/mikrotik/payments", tok_b,
               data={
                   "plan_id": plan["id"],
                   "sender_name": "اختبار سبرنت 9",
                   "transfer_receipt_number": "S9-TEST-001",
               },
               files={"receipt_image": ("receipt.png", png, "image/png")})
    print(f"[{c}]", json.dumps(r, ensure_ascii=False))
    req_id = (r.get("data") or {}).get("id")

    print("\n-- GET payments")
    c, r = api("GET", "/network-owner/mikrotik/payments", tok_b)
    print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:800])

    print("\n-- duplicate pending guard (expect 422)")
    c, r = api("POST", "/network-owner/mikrotik/payments", tok_b,
               data={"plan_id": plan["id"], "sender_name": "تكرار"})
    print(f"[{c}]", json.dumps(r, ensure_ascii=False))

    if req_id:
        section("3b) SSH — approve request (same atomic logic as Filament)")
        tinker(client, f"""
$r = App\\Models\\MikrotikPaymentRequest::findOrFail({req_id});
Illuminate\\Support\\Facades\\DB::transaction(function () use ($r) {{
    $r->update(['status' => 'approved', 'reviewed_by' => 1, 'reviewed_at' => now()]);
    App\\Models\\MikrotikSubscription::where('user_id', $r->user_id)
        ->whereIn('status', ['trial','active'])->update(['status' => 'expired']);
    App\\Models\\MikrotikSubscription::create([
        'user_id' => $r->user_id, 'plan_id' => $r->plan_id,
        'status' => 'active', 'starts_at' => now(),
        'ends_at' => now()->addDays($r->plan->duration_days),
    ]);
}});
echo 'approved #'.$r->id;
""")
        print("\n-- entitlements (778257546 after approval)")
        c, r = api("GET", "/network-owner/mikrotik/entitlements", tok_b)
        print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:800])

    section("4) Flip mikrotik.enforce=1")
    tinker(client,
           "App\\Models\\AppSetting::updateOrCreate(['key'=>'mikrotik.enforce'],"
           "['value'=>'1']); echo 'enforce='.App\\Models\\AppSetting::get('mikrotik.enforce');")
    run(client, f"cd {REMOTE_APP} && php artisan optimize:clear")

    print("\n-- entitlements 700000002 (active sub → all features)")
    c, r = api("GET", "/network-owner/mikrotik/entitlements", tok_a)
    print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:600])
    print("\n-- entitlements 778257546 (approved sub → all features)")
    c, r = api("GET", "/network-owner/mikrotik/entitlements", tok_b)
    print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:600])
    print("\n-- entitlements 700000003 (customer — no sub → free only)")
    tok_c = login("700000003")
    c, r = api("GET", "/network-owner/mikrotik/entitlements", tok_c)
    print(f"[{c}]", json.dumps(r, ensure_ascii=False)[:600])

    section("5) Final state")
    tinker(client,
           "echo json_encode(App\\Models\\MikrotikSubscription::with('plan:id,name')"
           "->get(['id','user_id','plan_id','status','ends_at'])"
           "->toArray(), JSON_UNESCAPED_UNICODE);")
    tinker(client,
           "echo json_encode(App\\Models\\MikrotikPaymentRequest::latest()->limit(3)"
           "->get(['id','user_id','plan_id','status','amount'])"
           "->toArray(), JSON_UNESCAPED_UNICODE);")
    tinker(client,
           "echo json_encode(App\\Models\\AppSetting::where('key','like','mikrotik.%')"
           "->pluck('value','key')->toArray(), JSON_UNESCAPED_UNICODE);")

    client.close()
    print("\nDone.")


if __name__ == "__main__":
    main()
