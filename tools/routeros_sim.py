"""
RouterOS API simulator for SaiberWiFi testing.
Speaks the real RouterOS API protocol (length-prefixed word sentences)
on 0.0.0.0:8728 so the Flutter app's router_os_client can connect.

v2: extended to satisfy MikroNet-style apps — covers hotspot, PPP,
user-manager, queues, live traffic monitor, health, files, scheduler.
Logs every received command to routeros_cmd_log.txt so we can map
exactly which RouterOS API calls a management app performs.

Auth: user=dev  password=dev123
"""
import socket
import threading
import sys
import os
import time
import random
import datetime
import hashlib

HOST = "0.0.0.0"
PORT = 8728
USER = "dev"
PASSWORD = "dev123"
# --legacy : emulate RouterOS < 6.43 — /login replies with an =ret=
# challenge and expects the MD5 challenge-response handshake.
LEGACY = "--legacy" in sys.argv
LEGACY_CHALLENGE = "0123456789abcdef0123456789abcdef"
LOGFILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "routeros_cmd_log.txt")
_loglock = threading.Lock()


def log_cmd(words):
    line = " ".join(words)
    with _loglock:
        with open(LOGFILE, "a", encoding="utf-8") as f:
            f.write(f"{datetime.datetime.now():%H:%M:%S.%f} | {line}\n")


# ---- RouterOS API wire protocol ------------------------------------------

def encode_len(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    if n < 0x4000:
        return bytes([0x80 | (n >> 8), n & 0xFF])
    if n < 0x200000:
        return bytes([0xC0 | (n >> 16), (n >> 8) & 0xFF, n & 0xFF])
    if n < 0x10000000:
        return bytes([0xE0 | (n >> 24), (n >> 16) & 0xFF,
                      (n >> 8) & 0xFF, n & 0xFF])
    return bytes([0xF0]) + n.to_bytes(4, "big")


def read_len(conn) -> int:
    b = conn.recv(1)
    if not b:
        raise ConnectionError("eof")
    c = b[0]
    if (c & 0x80) == 0:
        return c
    if (c & 0xC0) == 0x80:
        return ((c & 0x3F) << 8) | conn.recv(1)[0]
    if (c & 0xE0) == 0xC0:
        r = conn.recv(2)
        return ((c & 0x1F) << 16) | (r[0] << 8) | r[1]
    if (c & 0xF0) == 0xE0:
        r = conn.recv(3)
        return ((c & 0x0F) << 24) | (r[0] << 16) | (r[1] << 8) | r[2]
    r = conn.recv(4)
    return int.from_bytes(r, "big")


def read_exact(conn, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("eof")
        buf += chunk
    return buf


def read_sentence(conn) -> list:
    words = []
    while True:
        n = read_len(conn)
        if n == 0:
            return words
        words.append(read_exact(conn, n).decode("utf-8", "ignore"))


def send_sentence(conn, words: list):
    for w in words:
        b = w.encode("utf-8")
        conn.sendall(encode_len(len(b)) + b)
    conn.sendall(b"\x00")


# ---- Fake router state ----------------------------------------------------
# Each table is a list of attribute dicts; ".id" keys identify rows.

STATE = {
    "users": [
        {".id": "*1", "name": "TEST1234", "password": "TEST1234",
         "profile": "1M-1hour", "uptime": "0s", "disabled": "false",
         "bytes-in": "0", "bytes-out": "0", "comment": "saiberwifi-demo"},
        {".id": "*2", "name": "GUEST01", "password": "GUEST01",
         "profile": "default", "uptime": "2h15m", "disabled": "false",
         "bytes-in": "5042321", "bytes-out": "40211399",
         "comment": "card#A-2201"},
        {".id": "*3", "name": "OLD-USER", "password": "x",
         "profile": "512K", "uptime": "0s", "disabled": "true",
         "comment": "expired"},
        {".id": "*4", "name": "AHMED-5502", "password": "AHMED-5502",
         "profile": "2M-daily", "uptime": "35m", "disabled": "false",
         "bytes-in": "99321001", "bytes-out": "812900333",
         "comment": "card#A-2202"},
    ],
    "active": [
        {".id": "*8001", "user": "GUEST01", "address": "192.168.88.20",
         "uptime": "15m3s", "bytes-in": "1048576", "bytes-out": "5242880",
         "session-time-left": "45m", "mac-address": "A4:5E:60:11:22:33"},
        {".id": "*8002", "user": "AHMED-5502", "address": "192.168.88.31",
         "uptime": "7m41s", "bytes-in": "2097152", "bytes-out": "9048576",
         "mac-address": "B8:27:EB:44:55:66"},
    ],
    "profiles": [
        {".id": "*0", "name": "default", "rate-limit": "",
         "shared-users": "1"},
        {".id": "*1", "name": "512K", "rate-limit": "512k/512k",
         "shared-users": "1"},
        {".id": "*2", "name": "1M-1hour", "rate-limit": "1M/1M",
         "shared-users": "1", "session-timeout": "1h"},
        {".id": "*3", "name": "2M-daily", "rate-limit": "2M/2M",
         "shared-users": "5", "session-timeout": "1d"},
    ],
    "ppp_secrets": [
        {".id": "*A1", "name": "sub-saleh", "password": "p@ss1",
         "service": "pppoe", "profile": "ppp-4M", "disabled": "false",
         "last-logged-out": "oct/10/2026 21:44:00",
         "comment": "اشتراك شهري - حي المعلا"},
        {".id": "*A2", "name": "sub-nabil", "password": "p@ss2",
         "service": "pppoe", "profile": "ppp-8M", "disabled": "false",
         "comment": "اشتراك شهري - الشيخ عثمان"},
        {".id": "*A3", "name": "sub-old", "password": "p@ss3",
         "service": "pppoe", "profile": "ppp-4M", "disabled": "true",
         "comment": "متأخر عن السداد"},
    ],
    "ppp_active": [
        {".id": "*9001", "name": "sub-saleh", "service": "pppoe",
         "address": "10.10.10.2", "uptime": "3h12m",
         "caller-id": "C4:AD:34:77:88:99"},
    ],
    "ppp_profiles": [
        {".id": "*1", "name": "ppp-4M", "rate-limit": "4M/4M",
         "local-address": "10.10.10.1"},
        {".id": "*2", "name": "ppp-8M", "rate-limit": "8M/8M",
         "local-address": "10.10.10.1"},
    ],
    "um_users": [
        {".id": "*U1", "name": "um-khaled", "password": "u1",
         "disabled": "false", "shared-users": "1",
         "comment": "باقة 30 يوم"},
        {".id": "*U2", "name": "um-faisal", "password": "u2",
         "disabled": "false", "shared-users": "2"},
    ],
    "um_profiles": [
        {".id": "*1", "name": "um-1day", "price": "500",
         "validity": "1d"},
        {".id": "*2", "name": "um-30day", "price": "3500",
         "validity": "30d"},
    ],
    "queues": [
        {".id": "*Q1", "name": "q-saleh", "target": "10.10.10.2/32",
         "max-limit": "4M/4M", "disabled": "false"},
        {".id": "*Q2", "name": "q-nabil", "target": "10.10.10.3/32",
         "max-limit": "8M/8M", "disabled": "false"},
    ],
    "hotspot_servers": [
        {".id": "*1", "name": "hotspot1", "interface": "wlan1",
         "address-pool": "hs-pool", "profile": "hsprof1",
         "disabled": "false"},
    ],
    "dhcp_leases": [
        {".id": "*1", "address": "192.168.88.20",
         "mac-address": "A4:5E:60:11:22:33", "host-name": "Galaxy-A52",
         "status": "bound", "expires-after": "44m"},
        {".id": "*2", "address": "192.168.88.31",
         "mac-address": "B8:27:EB:44:55:66", "host-name": "Redmi-Note12",
         "status": "bound", "expires-after": "51m"},
        {".id": "*3", "address": "192.168.88.44",
         "mac-address": "F0:9F:C2:AA:BB:CC", "host-name": "DESKTOP-9Q2",
         "status": "bound", "expires-after": "30m"},
    ],
    "wireless_reg": [
        {"interface": "wlan1", "mac-address": "A4:5E:60:11:22:33",
         "uptime": "15m3s", "signal-strength": "-58dBm",
         "tx-rate": "72.2Mbps", "rx-rate": "72.2Mbps"},
        {"interface": "wlan1", "mac-address": "B8:27:EB:44:55:66",
         "uptime": "7m41s", "signal-strength": "-71dBm",
         "tx-rate": "54Mbps", "rx-rate": "54Mbps"},
    ],
    "arp": [
        {".id": "*1", "address": "192.168.88.20",
         "mac-address": "A4:5E:60:11:22:33", "interface": "wlan1"},
        {".id": "*2", "address": "192.168.88.31",
         "mac-address": "B8:27:EB:44:55:66", "interface": "wlan1"},
    ],
    "ip_addresses": [
        {".id": "*1", "address": "192.168.88.1/24", "network": "192.168.88.0",
         "interface": "wlan1", "disabled": "false"},
        {".id": "*2", "address": "10.10.10.1/24", "network": "10.10.10.0",
         "interface": "ether1", "disabled": "false"},
    ],
    "pools": [
        {".id": "*1", "name": "hs-pool",
         "ranges": "192.168.88.10-192.168.88.250"},
    ],
    "schedulers": [
        {".id": "*1", "name": "nightly-reboot", "interval": "1d",
         "on-event": "/system/reboot", "disabled": "true"},
    ],
    "scripts": [
        {".id": "*1", "name": "cleanup-expired",
         "source": ":log info \"cleanup ran\"", "disabled": "false"},
    ],
    "files": [
        {".id": "*1", "name": "flash", "type": "directory"},
        {".id": "*2", "name": "flash/hotspot", "type": "directory"},
        {".id": "*3", "name": "flash/hotspot/login.html",
         "type": "file", "size": "4122"},
        {".id": "*4", "name": "flash/hotspot/status.html",
         "type": "file", "size": "2055"},
    ],
    "logs": [
        {"time": "oct/12/2026 04:10:11", "topics": "system,info",
         "message": "router rebooted"},
        {"time": "oct/12/2026 04:10:20", "topics": "hotspot,info",
         "message": "GUEST01 logged in"},
        {"time": "oct/12/2026 04:25:02", "topics": "pppoe,info",
         "message": "sub-saleh connected"},
        {"time": "oct/12/2026 04:31:47", "topics": "error,dhcp",
         "message": "dhcp-server lease conflict on wlan1"},
    ],
    "neighbors": [
        {"identity": "RB750-Office", "address": "10.10.10.2",
         "mac-address": "4C:5E:0C:11:22:33", "interface": "ether1",
         "version": "7.16.1", "board": "RB750r2", "uptime": "2d5h"},
        {"identity": "hAP-Home", "address": "192.168.88.25",
         "mac-address": "48:8F:5A:44:55:66", "interface": "wlan1",
         "version": "7.15.3", "board": "hAP-ac2", "uptime": "1d"},
    ],
    "hosts": [
        {".id": "*1", "mac-address": "A4:5E:60:11:22:33",
         "address": "192.168.88.20", "server": "hotspot1",
         "uptime": "15m3s", "authorized": "true"},
        {".id": "*2", "mac-address": "B8:27:EB:44:55:66",
         "address": "192.168.88.31", "server": "hotspot1",
         "uptime": "7m41s", "authorized": "true"},
    ],
    "netwatch": [
        {".id": "*1", "host": "8.8.8.8", "type": "simple",
         "interval": "1m", "timeout": "1000", "status": "up",
         "comment": "فحص الإنترنت", "disabled": "false"},
        {".id": "*2", "host": "10.10.10.254", "type": "simple",
         "interval": "30s", "timeout": "1000", "status": "down",
         "disabled": "false"},
    ],
    "routes": [
        {".id": "*1", "dst-address": "0.0.0.0/0",
         "gateway": "10.10.10.1", "distance": "1",
         "disabled": "false", "comment": "WAN"},
        {".id": "*2", "dst-address": "192.168.88.0/24",
         "gateway": "wlan1", "distance": "0",
         "disabled": "false", "comment": "LAN"},
    ],
    "dhcp_servers": [
        {".id": "*1", "name": "dhcp-lan", "interface": "wlan1",
         "address-pool": "hs-pool", "lease-time": "10m",
         "disabled": "false"},
    ],
    "dhcp_clients": [
        {".id": "*1", "interface": "ether1", "status": "bound",
         "address": "10.10.10.5/24", "use-peer-dns": "yes",
         "disabled": "false"},
    ],
    "dns_static": [
        {".id": "*1", "name": "router.local",
         "address": "192.168.88.1", "comment": "الراوتر",
         "disabled": "false"},
    ],
    "nat_rules": [
        {".id": "*1", "chain": "srcnat", "action": "masquerade",
         "out-interface": "ether1", "comment": "تمويه WAN",
         "disabled": "false"},
    ],
    "filter_rules": [
        {".id": "*1", "chain": "input", "action": "accept",
         "protocol": "icmp", "comment": "السماح بالبنج",
         "disabled": "false"},
        {".id": "*2", "chain": "input", "action": "drop",
         "src-address": "0.0.0.0/0", "in-interface": "ether1",
         "protocol": "tcp", "dst-port": "23",
         "comment": "حظر Telnet من WAN", "disabled": "false"},
    ],
    "mangle_rules": [
        {".id": "*1", "chain": "prerouting",
         "action": "mark-connection",
         "new-connection-mark": "youtube-conn",
         "layer7-protocol": "youtube", "comment": "وسم يوتيوب",
         "disabled": "false"},
    ],
    "address_lists": [
        {".id": "*1", "list": "blocked-sites",
         "address": "ads.example.com", "timeout": "",
         "comment": "مواقع إعلانية", "disabled": "false"},
    ],
    "layer7": [
        {".id": "*1", "name": "youtube",
         "regexp": "^.+(youtube.com|youtu.be).*$",
         "disabled": "false"},
    ],
    "connections": [
        {".id": "*1", "src-address": "192.168.88.20:52344",
         "dst-address": "142.250.74.46:443", "protocol": "tcp",
         "tcp-state": "established"},
        {".id": "*2", "src-address": "192.168.88.31:51230",
         "dst-address": "8.8.8.8:53", "protocol": "udp",
         "tcp-state": ""},
    ],
    "bindings": [
        {".id": "*1", "address": "192.168.88.99",
         "mac-address": "00:11:22:33:44:55", "type": "blocked",
         "comment": "جهاز محظور", "disabled": "false"},
    ],
    "sys_users": [
        {".id": "*1", "name": "admin", "group": "full",
         "disabled": "false", "last-logged-in": "oct/12/2026 03:00:00"},
        {".id": "*2", "name": "viewer", "group": "read",
         "disabled": "false", "comment": "حساب عرض فقط"},
    ],
    "sys_groups": [
        {".id": "*1", "name": "read", "policy": "read",
         "disabled": "false"},
        {".id": "*2", "name": "write",
         "policy": "read,write,policy,test", "disabled": "false"},
        {".id": "*3", "name": "full",
         "policy": "read,write,policy,test,reboot,sniff,sensitive,"
                   "api,winbox,web,ftp,telnet,ssh",
         "disabled": "false"},
    ],
    "hs_profiles": [
        {".id": "*1", "name": "hsprof1", "html-directory": "hotspot",
         "login-by": "http-chap,http-pap",
         "http-cookie-lifetime": "1d", "disabled": "false"},
    ],
    "ip_cloud": {
        "ddns-enabled": "no", "ddns-update-interval": "none",
        "update-time": "yes", "public-address": "134.35.22.10",
        "public-address-ipv6": "", "warning": "",
        "status": "updated",
        "dns-name": "a1b2c3d4e5.sn.mynetname.net",
    },
    "services": [
        {".id": "*1", "name": "telnet", "port": "23",
         "disabled": "true", "address": ""},
        {".id": "*2", "name": "ftp", "port": "21",
         "disabled": "true", "address": ""},
        {".id": "*3", "name": "www", "port": "80",
         "disabled": "true", "address": ""},
        {".id": "*4", "name": "ssh", "port": "22",
         "disabled": "false", "address": ""},
        {".id": "*5", "name": "winbox", "port": "8291",
         "disabled": "false", "address": ""},
        {".id": "*6", "name": "api", "port": "8728",
         "disabled": "false", "address": ""},
        {".id": "*7", "name": "api-ssl", "port": "8729",
         "disabled": "true", "address": "", "certificate": "none"},
    ],
    "certificates": [],
    "next_ids": {"users": 5, "ppp_secrets": 4, "um_users": 3,
                 "profiles": 4, "ppp_profiles": 3, "queues": 3,
                 "schedulers": 2, "scripts": 2, "files": 5,
                 "netwatch": 3, "hosts": 3, "routes": 3,
                 "dhcp_servers": 2, "dhcp_clients": 2,
                 "dns_static": 2, "nat_rules": 2, "filter_rules": 3,
                 "mangle_rules": 2, "address_lists": 2,
                 "layer7": 2, "bindings": 2, "services": 8,
                 "certificates": 1},
}

RESOURCE = {
    "uptime": "3d4h12m33s", "version": "7.16.1 (stable)",
    "board-name": "RB941-2nD", "platform": "MikroTik",
    "cpu-load": "14", "free-memory": "42000000",
    "total-memory": "67108864", "cpu-count": "1",
    "free-hdd-space": "88000000", "total-hdd-space": "134217728",
    "architecture-name": "arm", "build-time": "2025-09-10 10:00:00",
    "factory-software": "6.48.6",
}

IDENTITY = {"name": "SaiberTest-Router"}

if LEGACY:
    RESOURCE["version"] = "6.40.9 (long-term)"
    IDENTITY["name"] = "SaiberTest-Router-v6"

INTERFACES = [
    {".id": "*1", "name": "ether1", "type": "ether", "running": "true",
     "disabled": "false", "rx-byte": "88123456", "tx-byte": "44512321",
     "default-name": "ether1"},
    {".id": "*2", "name": "wlan1", "type": "wlan", "running": "true",
     "disabled": "false", "rx-byte": "512345678", "tx-byte": "1203456789",
     "default-name": "wlan1", "ssid": "SaiberNet"},
    {".id": "*3", "name": "bridge1", "type": "bridge", "running": "true",
     "disabled": "false", "rx-byte": "512345678",
     "tx-byte": "1203456789"},
]

HEALTH = {"temperature": "47.5", "cpu-temperature": "52.3",
          "voltage": "24.1", "fan1-speed": "0"}

CLOCK = {"time": "05:20:00", "date": "oct/12/2026",
         "time-zone-name": "Asia/Aden", "gmt-offset": "+03:00"}

# cmd prefix -> state table key (for generic print/add/set/remove/enable/disable)
TABLE_MAP = {
    "/ip/hotspot/user": "users",
    "/ip/hotspot/active": "active",
    "/ip/hotspot/user/profile": "profiles",
    "/ip/hotspot/server": "hotspot_servers",
    "/ppp/secret": "ppp_secrets",
    "/ppp/active": "ppp_active",
    "/ppp/profile": "ppp_profiles",
    "/user-manager/user": "um_users",
    "/user-manager/profile": "um_profiles",
    "/user-manager/user/profile": "um_profiles",
    "/queue/simple": "queues",
    "/ip/dhcp-server/lease": "dhcp_leases",
    "/interface/wireless/registration-table": "wireless_reg",
    "/ip/arp": "arp",
    "/ip/address": "ip_addresses",
    "/ip/pool": "pools",
    "/ip/neighbor": "neighbors",
    "/ip/hotspot/host": "hosts",
    "/ip/route": "routes",
    "/ip/dhcp-server": "dhcp_servers",
    "/ip/dhcp-client": "dhcp_clients",
    "/ip/dns/static": "dns_static",
    "/ip/firewall/nat": "nat_rules",
    "/ip/firewall/filter": "filter_rules",
    "/ip/firewall/mangle": "mangle_rules",
    "/ip/firewall/address-list": "address_lists",
    "/ip/firewall/layer7-protocol": "layer7",
    "/ip/firewall/connection": "connections",
    "/ip/hotspot/ip-binding": "bindings",
    "/tool/netwatch": "netwatch",
    "/user/group": "sys_groups",
    "/user": "sys_users",
    "/ip/hotspot/profile": "hs_profiles",
    "/system/scheduler": "schedulers",
    "/system/script": "scripts",
    "/file": "files",
    "/log": "logs",
    "/ip/hotspot/user/limitation": "profiles",
    "/ip/service": "services",
    "/certificate": "certificates",
}


def row(d):
    return ["!re"] + [f"={k}={v}" for k, v in d.items()]


def apply_proplist(rows, proplist):
    if not proplist:
        return rows
    keys = proplist.split(",")
    out = []
    for r in rows:
        out.append({k: r[k] for k in keys if k in r})
    return out


def find_table(cmd):
    """Match longest prefix in TABLE_MAP."""
    best = None
    for pfx in TABLE_MAP:
        if cmd.startswith(pfx):
            if best is None or len(pfx) > len(best):
                best = pfx
    return best


def handle(cmd_words, conn, logged_in, streams):
    words = [w for w in cmd_words if w and not w.startswith(".tag=")]
    tag = next((w for w in cmd_words if w.startswith(".tag=")), None)
    cmd = words[0] if words else ""
    params = {}
    queries = []
    for w in words[1:]:
        if w.startswith("=") and "=" in w[1:]:
            k, v = w[1:].split("=", 1)
            params[k] = v
        elif w.startswith("?"):
            queries.append(w)

    def finish(extra=None, ret=None):
        out = list(extra or [])
        done = ["!done"]
        if ret is not None:
            done.append(f"=ret={ret}")
        if tag:
            done.append(tag)
        out.append(done)
        for s in out:
            send_sentence(conn, s)

    def trap(msg):
        send_sentence(conn, ["!trap", f"=message={msg}"])
        send_sentence(conn, ["!done"])

    if cmd == "/login":
        if LEGACY:
            if "response" in params:
                expected = "00" + hashlib.md5(
                    b"\x00" + PASSWORD.encode()
                    + bytes.fromhex(LEGACY_CHALLENGE)
                ).hexdigest()
                if params.get("name") == USER \
                        and params["response"] == expected:
                    finish()
                    return True
                trap("cannot log in")
                return logged_in
            finish(ret=LEGACY_CHALLENGE)
            return logged_in
        if params.get("name") == USER and params.get("password") == PASSWORD:
            finish()
            return True
        trap("cannot log in")
        return logged_in

    if cmd == "/login" and "ret" not in params:
        pass  # already handled above

    if not logged_in:
        trap("no permissions")
        return logged_in

    if cmd == "/cancel":
        st = streams.pop(tag, None) or streams.pop(params.get("tag"), None)
        if st:
            st.set()
        finish()
        return logged_in

    # --- one-shot system endpoints ------------------------------------
    if cmd == "/system/identity/print":
        finish([row(IDENTITY)])
    elif cmd == "/system/identity/set":
        IDENTITY["name"] = params.get("name", IDENTITY["name"])
        finish()
    elif cmd == "/system/resource/print":
        RESOURCE["cpu-load"] = str(random.randint(4, 40))
        finish([row(apply_proplist([RESOURCE], params.get(".proplist"))[0])])
    elif cmd in ("/system/health/print", "/system/routerboard/print"):
        finish([row(HEALTH)])
    elif cmd == "/system/clock/print":
        CLOCK["time"] = datetime.datetime.now().strftime("%H:%M:%S")
        finish([row(CLOCK)])
    elif cmd == "/system/package/print":
        finish([row({"name": "routeros-arm", "version": "7.16.1",
                     "disabled": "false"}),
                row({"name": "user-manager", "version": "7.16.1",
                     "disabled": "false"}),
                row({"name": "hotspot", "version": "7.16.1",
                     "disabled": "false"})])
    elif cmd == "/system/license/print":
        finish([row({"software-id": "SIM-TEST-1234",
                     "serial-number": "SIMSN0001",
                     "nlevel": "6", "features": ""})])
    elif cmd in ("/system/reboot", "/system/shutdown"):
        finish()
    elif cmd == "/system/backup/save":
        STATE["files"].append({
            ".id": "*B1", "name": params.get("name", "backup") + ".backup",
            "type": "backup", "size": "524288"})
        finish()
    elif cmd == "/system/backup/load":
        finish()
    elif cmd == "/system/script/run":
        finish()
    elif cmd == "/export" or cmd.endswith("/export"):
        finish([row({"name": "export"})])
    elif cmd == "/interface/print":
        finish([row(i) for i in INTERFACES])
    elif cmd.startswith("/interface/monitor"):
        # /interface/monitor-traffic or /interface/monitor (numbers=, once=)
        def traffic_row():
            return {"name": params.get("interface",
                                       params.get("numbers", "ether1")),
                    "rx-bits-per-second": str(random.randint(2_000_000,
                                                           9_000_000)),
                    "tx-bits-per-second": str(random.randint(1_000_000,
                                                           5_000_000)),
                    "rx-packets-per-second": str(random.randint(200, 900)),
                    "tx-packets-per-second": str(random.randint(150, 600))}
        interval = params.get("interval")
        if interval:
            # streaming mode: send !re periodically until /cancel or disconnect
            stop = threading.Event()
            streams[tag or cmd] = stop

            def sender():
                try:
                    while not stop.is_set():
                        send_sentence(conn, row(traffic_row()) +
                                      ([tag] if tag else []))
                        stop.wait(float(interval.rstrip("s") or 1))
                except OSError:
                    stop.set()

            threading.Thread(target=sender, daemon=True).start()
        else:
            finish([row(traffic_row())])
    elif cmd == "/tool/torch":
        finish([row({"src-address": "192.168.88.20",
                     "dst-address": "8.8.8.8", "protocol": "tcp",
                     "tx": "1048576", "rx": "524288"})])
    elif cmd == "/ping":
        cnt = int(params.get("count", "4") or 4)
        rows = []
        for i in range(min(cnt, 20)):
            rows.append(row({
                "host": params.get("address", ""),
                "seq": str(i), "size": "64", "ttl": "64",
                "time": str(random.randint(1, 60))}))
        finish(rows)
    elif cmd == "/tool/fetch":
        dst = params.get("dst-path", "")
        if dst:
            # simulate the router saving the downloaded file to disk —
            # create the file entry (and parent dir entry) in /file.
            STATE["next_ids"].setdefault("files", 50)
            existing = {f.get("name") for f in STATE["files"]}
            parts = dst.split("/")
            for i in range(1, len(parts)):
                d = "/".join(parts[:i])
                if d not in existing:
                    STATE["files"].append({
                        ".id": f"*D{len(STATE['files'])}",
                        "name": d, "type": "directory"})
            if dst not in existing:
                STATE["files"].append({
                    ".id": f"*F{len(STATE['files'])}",
                    "name": dst,
                    "type": ".js file" if dst.endswith(".js") else "file",
                    "size": "4096",
                    "creation-time": "nov/02/2026 00:00:00"})
        finish([row({"status": "finished", "duration": "1s",
                     "total-time": "1s", "downloaded": "1024",
                     "size": "1024",
                     "url": params.get("url", "")})])
    elif cmd in ("/system/note/print",):
        finish([row({"note": "SaiberWiFi test router"})])
    elif cmd == "/ip/cloud/print":
        finish([row(STATE["ip_cloud"])])
    elif cmd == "/ip/cloud/set":
        STATE["ip_cloud"].update(
            {k: v for k, v in params.items() if k != "numbers"})
        if params.get("ddns-enabled") == "yes":
            STATE["ip_cloud"]["status"] = "updated"
        finish()
    elif cmd == "/certificate/sign":
        num = params.get("numbers", "")
        for c in STATE["certificates"]:
            if c.get(".id") == num or c.get("name") == num:
                c["signed"] = "yes"
                c["issuer"] = "self-signed"
        finish()
    else:
        # --- generic table operations -----------------------------------
        pfx = find_table(cmd)
        if pfx and cmd.startswith(pfx):
            table = STATE.get(TABLE_MAP[pfx], [])
            op = cmd[len(pfx):]
            if op == "/print" or op == "":
                rows = apply_proplist(table, params.get(".proplist"))
                if params.get("count-only") == "" or \
                        any(q.startswith("?") and "count" in q
                            for q in queries) or \
                        params.get("count-only") is not None:
                    finish(ret=len(rows))
                else:
                    finish([row(r) for r in rows])
            elif op == "/add":
                nid = STATE["next_ids"][TABLE_MAP[pfx]] \
                    if TABLE_MAP[pfx] in STATE["next_ids"] else 1
                rec = {".id": f"*{nid}"}
                for k, v in params.items():
                    rec[k] = v
                rec.setdefault("disabled", "false")
                table.append(rec)
                if TABLE_MAP[pfx] in STATE["next_ids"]:
                    STATE["next_ids"][TABLE_MAP[pfx]] += 1
                finish(ret=rec[".id"])
            elif op == "/set":
                num = params.get("numbers", "")
                for r in table:
                    if r.get(".id") == num or r.get("name") == num:
                        for k, v in params.items():
                            if k not in ("numbers",):
                                r[k] = v
                finish()
            elif op == "/remove":
                nums = params.get("numbers", "").split(",")
                table[:] = [r for r in table
                            if r.get(".id") not in nums
                            and r.get("name") not in nums]
                finish()
            elif op == "/enable":
                nums = params.get("numbers", "").split(",")
                for r in table:
                    if r.get(".id") in nums or r.get("name") in nums:
                        r["disabled"] = "false"
                finish()
            elif op == "/disable":
                nums = params.get("numbers", "").split(",")
                for r in table:
                    if r.get(".id") in nums or r.get("name") in nums:
                        r["disabled"] = "true"
                finish()
            else:
                finish()
        else:
            finish()

    return logged_in


def client_thread(conn, addr):
    print(f"[+] connection from {addr}", flush=True)
    logged_in = False
    streams = {}
    try:
        while True:
            words = read_sentence(conn)
            if not words:
                continue
            log_cmd(words)
            logged_in = handle(words, conn, logged_in, streams)
    except (ConnectionError, OSError):
        pass
    finally:
        for st in streams.values():
            st.set()
        conn.close()
        print(f"[-] disconnected {addr}", flush=True)


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(16)
    print(f"RouterOS API simulator listening on {HOST}:{PORT}", flush=True)
    print(f"login -> user={USER} password={PASSWORD}", flush=True)
    print(f"command log -> {LOGFILE}", flush=True)
    while True:
        conn, addr = srv.accept()
        threading.Thread(target=client_thread, args=(conn, addr),
                         daemon=True).start()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
