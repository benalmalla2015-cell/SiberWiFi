"""Activate accounting subscription for owner 781522269 (id=108) on staging,
then verify via API with a temp Sanctum token."""
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
        # Grant: expire any old actives, create active sub on plan 1.
        run(
            f"cd {REMOTE_APP} && php artisan tinker --execute='"
            "$u = App\\Models\\User::where(\"phone\",\"781522269\")->firstOrFail();"
            "echo \"user_id=\".$u->id.\" type=\".$u->type.\"\n\";"
            "App\\Models\\AccSubscription::where(\"network_owner_id\",$u->id)"
            "->whereIn(\"status\",[\"active\",\"trial\"])"
            "->update([\"status\"=>\"expired\",\"ends_at\"=>now()]);"
            "$plan = App\\Models\\AccPlan::where(\"is_active\",true)->first();"
            "$s = App\\Models\\AccSubscription::create(["
            "\"network_owner_id\"=>$u->id,\"plan_id\"=>$plan->id,"
            "\"status\"=>\"active\",\"starts_at\"=>now(),"
            "\"ends_at\"=>now()->addDays($plan->duration_days)]);"
            "echo \"created sub \".$s->id.\" plan=\".$plan->name"
            ".\" ends=\".$s->ends_at.\"\n\";'"
        )

        # Verify via API with a temp token.
        code, tok_out = run(
            f"cd {REMOTE_APP} && php artisan tinker --execute='"
            "$u = App\\Models\\User::where(\"phone\",\"781522269\")->first();"
            "echo $u->createToken(\"verify-tmp\")->plainTextToken;'"
        )
        token = tok_out.strip().splitlines()[-1].strip()
        print(f"token: {token[:12]}...")

        import urllib.request
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        for path in ("/network-owner/accounting/me",
                     "/network-owner/accounting/billing/entitlements"):
            req = urllib.request.Request(
                f"https://staging.saiberwifi.net/api{path}",
                headers={"Accept": "application/json",
                         "Authorization": f"Bearer {token}"})
            try:
                with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
                    print(f"GET {path} => {r.status}")
                    print(r.read().decode()[:500] + "\n")
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
