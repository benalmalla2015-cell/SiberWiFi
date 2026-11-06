"""Create a dedicated staging network-owner for the ADB test device.

Account 700000002 is shared across test sessions and every login revokes
previous sanctum tokens — the device keeps getting force-logged-out. This
creates 700000099 / 123456 used ONLY by the phone.
"""
import os
import re
import sys

import paramiko

sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"C:\Users\HP\Desktop\saiberwifi"
REMOTE_APP = "/home/u170359695/domains/saiberwifi.net/staging-app"

_src = open(os.path.join(ROOT, "staging_deploy.py"), encoding="utf-8").read()
HOST = re.search(r"ssh\.connect\('([^']+)'", _src).group(1)
PORT = int(re.search(r"port=(\d+)", _src).group(1))
USER = re.search(r"username='([^']+)'", _src).group(1)
PASSWORD = re.search(r"password='([^']+)'", _src).group(1)

PHP = (
    r"$ref = \App\Models\User::where('phone','700000002')->firstOrFail();"
    r"$u = \App\Models\User::firstOrCreate("
    r"['phone'=>'700000099'],"
    r"['name'=>'MikroTik ADB Test Owner',"
    r"'password'=>bcrypt('123456'),"
    r"'type'=>'network_owner','is_active'=>true,"
    r"'account_number'=>'700000099',"
    r"'region_id'=>$ref->region_id,"
    r"'directorate_id'=>$ref->directorate_id,"
    r"'sub_directorate_id'=>$ref->sub_directorate_id,"
    r"'region_type'=>$ref->region_type]);"
    r"\App\Models\NetworkOwner::firstOrCreate(['user_id'=>$u->id],"
    r"['business_name'=>'ADB Test Net','is_approved'=>true]);"
    r"echo $u->id.':'.$u->phone;"
)

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=30)
esc = PHP.replace("'", "'\\''")
cmd = f"cd {REMOTE_APP} && php artisan tinker --execute='{esc}'"
_, out, err = client.exec_command(cmd, timeout=90)
print(out.read().decode())
e = err.read().decode().strip()
if e:
    print("STDERR:", e[:2000])
client.close()
