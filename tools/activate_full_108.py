"""Full activation check for owner 781522269 on staging:
accounting sub (should exist) + MikroTik sub (grant if missing),
then verify both entitlement endpoints."""
import os
import re
import sys
import time

import paramiko

sys.stdout.reconfigure(encoding='utf-8')

ROOT = r"C:\Users\HP\Desktop\saiberwifi"
REMOTE_APP = "/home/u170359695/domains/saiberwifi.net/staging-app"

_src = open(os.path.join(ROOT, "staging_deploy.py"), encoding="utf-8").read()
HOST = re.search(r"ssh\.connect\('([^']+)'", _src).group(1)
PORT = int(re.search(r"port=(\d+)", _src).group(1))
USER = re.search(r"username='([^']+)'", _src).group(1)
PASSWORD = re.search(r"password='([^']+)'", _src).group(1)


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
        _, out, err = client.exec_command(cmd)
        code = out.channel.recv_exit_status()
        o = out.read().decode(errors="replace")
        e = err.read().decode(errors="replace")
        if o:
            print(o)
        if e:
            print(e, file=sys.stderr)
        return code, o

    try:
        run(
            f"cd {REMOTE_APP} && php artisan tinker --execute='"
            "$u = App\\Models\\User::where(\"phone\",\"781522269\")->firstOrFail();"
            "echo \"user_id=\".$u->id.\"\n\";"
            # ── MikroTik subscription ──
            "$ms = App\\Models\\MikrotikSubscription::where(\"user_id\",$u->id)"
            "->whereIn(\"status\",[\"active\",\"trial\"])->first();"
            "if($ms){ echo \"mikrotik already \".$ms->status.\"\n\"; }"
            "else {"
            "App\\Models\\MikrotikSubscription::where(\"user_id\",$u->id)"
            "->whereIn(\"status\",[\"active\",\"trial\"])"
            "->update([\"status\"=>\"expired\",\"ends_at\"=>now()]);"
            "$mp = App\\Models\\MikrotikPlan::where(\"is_active\",true)"
            "->orderBy(\"price\")->first();"
            "$s = App\\Models\\MikrotikSubscription::create(["
            "\"user_id\"=>$u->id,\"plan_id\"=>$mp->id,"
            "\"status\"=>\"active\",\"starts_at\"=>now(),"
            "\"ends_at\"=>now()->addDays($mp->duration_days)]);"
            "echo \"mikrotik created #\".$s->id.\" plan=\".$mp->name"
            ".\" ends=\".$s->ends_at.\"\n\"; }"
            # ── Accounting subscription ──
            "$as = App\\Models\\AccSubscription::where(\"network_owner_id\",$u->id)"
            "->whereIn(\"status\",[\"active\",\"trial\"])->first();"
            "echo \"acc \".($as ? $as->status.\" ends=\".$as->ends_at : \"MISSING\").\"\n\";'"
        )

        # Verify via API with a temp token.
        code, tok_out = run(
            f"cd {REMOTE_APP} && php artisan tinker --execute='"
            "$u = App\\Models\\User::where(\"phone\",\"781522269\")->first();"
            "echo $u->createToken(\"verify-tmp\")->plainTextToken;'"
        )
        token = tok_out.strip().splitlines()[-1].strip()

        import urllib.request
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        for path in ("/network-owner/mikrotik/entitlements",
                     "/network-owner/accounting/billing/entitlements"):
            req = urllib.request.Request(
                f"https://staging.saiberwifi.net/api{path}",
                headers={"Accept": "application/json",
                         "Authorization": f"Bearer {token}"})
            try:
                with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
                    print(f"GET {path} => {r.status}")
                    print(r.read().decode()[:400] + "\n")
            except urllib.error.HTTPError as e:
                print(f"GET {path} => {e.code} {e.read().decode()[:300]}")

        run(
            f"cd {REMOTE_APP} && php artisan tinker --execute='"
            "App\\Models\\User::where(\"phone\",\"781522269\")->first()"
            "->tokens()->where(\"name\",\"verify-tmp\")->delete();"
            "echo \"token deleted\";'"
        )
    finally:
        client.close()


if __name__ == "__main__":
    main()
