"""Find a trial/unpaid owner on staging and verify the premium gate 403."""
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
        tinker = (
            "cd %s && php artisan tinker --execute=" % REMOTE_APP
            + "'"
            + "$owners = DB::table(\"users\")"
            + "->where(\"type\",\"network_owner\")"
            + "->limit(15)->get([\"id\",\"phone\",\"name\"]);"
            + "foreach($owners as $u){"
            + "$s = DB::table(\"mikrotik_subscriptions\")"
            + "->where(\"user_id\",$u->id)"
            + "->orderByDesc(\"ends_at\")->first();"
            + "echo $u->id.\"|\".$u->phone.\"|\".($s ? $s->status.\"|\".$s->ends_at : \"none\").\"\n\";}"
            + "'"
        )
        run(tinker)
    finally:
        client.close()


if __name__ == "__main__":
    main()
