"""Issue a Sanctum token for a no-subscription owner on staging,
then verify premium render is 403 while free render is 200."""
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
        # Token for user 108 (no subscription) — temporary, deleted after.
        code, tok_out = run(
            f"cd {REMOTE_APP} && php artisan tinker --execute='"
            "$u = App\\Models\\User::find(108);"
            "$t = $u->createToken(\"gate-test\");"
            "echo $t->plainTextToken;'"
        )
        token = tok_out.strip().splitlines()[-1].strip()
        print(f"token issued: {token[:12]}...")

        import urllib.request
        import json as _json
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        def call(tid):
            req = urllib.request.Request(
                "https://staging.saiberwifi.net/api/network-owner/"
                "mikrotik/page-templates/render",
                data=_json.dumps({"template_id": tid}).encode(),
                headers={"Content-Type": "application/json",
                         "Accept": "application/json",
                         "Authorization": f"Bearer {token}"},
                method="POST")
            try:
                with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
                    return r.status, r.read().decode()[:160]
            except urllib.error.HTTPError as e:
                return e.code, e.read().decode()[:160]

        for tid in ("royal", "ocean", "duo", "neo"):
            code, body = call(tid)
            print(f"render {tid}: {code} {body}")

        # Cleanup the test token.
        run(
            f"cd {REMOTE_APP} && php artisan tinker --execute='"
            "App\\Models\\User::find(108)->tokens()"
            "->where(\"name\",\"gate-test\")->delete();"
            "echo \"token deleted\";"
            "'"
        )
    finally:
        client.close()


if __name__ == "__main__":
    main()
