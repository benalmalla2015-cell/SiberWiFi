"""
RouterOS API simulator for SaiberWiFi testing.
Speaks the real RouterOS API protocol (length-prefixed word sentences)
on 0.0.0.0:8728 so the Flutter app's router_os_client can connect.

Auth: user=dev  password=dev123
"""
import socket
import threading
import sys

HOST = "0.0.0.0"
PORT = 8728
USER = "dev"
PASSWORD = "dev123"

# ---- RouterOS API wire protocol ------------------------------------------

def encode_len(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    if n < 0x4000:
        return bytes([0x80 | (n >> 8), n & 0xFF])
    if n < 0x200000:
        return bytes([0xC0 | (n >> 16), (n >> 8) & 0xFF, n & 0xFF])
    if n < 0x10000000:
        return bytes([0xE0 | (n >> 24), (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])
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

STATE = {
    "users": [
        {".id": "*1", "name": "TEST1234", "password": "TEST1234",
         "profile": "1M-1hour", "uptime": "0s", "disabled": "false",
         "comment": "saiberwifi-demo"},
        {".id": "*2", "name": "GUEST01", "password": "GUEST01",
         "profile": "default", "uptime": "2h15m", "disabled": "false"},
        {".id": "*3", "name": "OLD-USER", "password": "x",
         "profile": "512K", "uptime": "0s", "disabled": "true"},
    ],
    "active": [
        {"user": "GUEST01", "address": "192.168.88.20",
         "uptime": "15m3s", "bytes-in": "1048576", "bytes-out": "5242880"},
    ],
    "profiles": [
        {"name": "default", "rate-limit": "", "shared-users": "1"},
        {"name": "512K", "rate-limit": "512k/512k", "shared-users": "1"},
        {"name": "1M-1hour", "rate-limit": "1M/1M", "shared-users": "1"},
        {"name": "2M-daily", "rate-limit": "2M/2M", "shared-users": "5"},
    ],
    "next_id": 4,
}

RESOURCE = {
    "uptime": "3d4h12m33s", "version": "7.16.1 (stable)",
    "board-name": "RB941-2nD", "platform": "MikroTik",
    "cpu-load": "14", "free-memory": "42000000",
    "total-memory": "67108864", "cpu-count": "1",
}

def row(words):
    """Build a !re sentence from attr dict."""
    return ["!re"] + [f"={k}={v}" for k, v in words.items()]

def handle(cmd_words, conn, logged_in):
    words = [w for w in cmd_words if w and not w.startswith(".tag=")]
    tag = next((w for w in cmd_words if w.startswith(".tag=")), None)
    cmd = words[0] if words else ""
    params = {}
    for w in words[1:]:
        if w.startswith("=") and "=" in w[1:]:
            k, v = w[1:].split("=", 1)
            params[k] = v

    def finish(extra=None):
        out = extra or []
        if tag:
            out.append(["!done", tag])
        else:
            out.append(["!done"])
        for s in out:
            send_sentence(conn, s)

    if cmd == "/login":
        if params.get("name") == USER and params.get("password") == PASSWORD:
            finish()
            return True
        send_sentence(conn, ["!trap", "=message=cannot log in"])
        send_sentence(conn, ["!done"])
        return logged_in

    if not logged_in:
        send_sentence(conn, ["!trap", "=message=no permissions"])
        send_sentence(conn, ["!done"])
        return logged_in

    if cmd == "/system/identity/print":
        finish([row({"name": "SaiberTest-Router"})])
    elif cmd == "/system/resource/print":
        finish([row(RESOURCE)])
    elif cmd == "/interface/print":
        finish([row({"name": "ether1", "type": "ether", "running": "true"}),
                row({"name": "wlan1", "type": "wlan", "running": "true"})])
    elif cmd == "/ip/hotspot/user/print":
        finish([row(u) for u in STATE["users"]])
    elif cmd == "/ip/hotspot/active/print":
        finish([row(a) for a in STATE["active"]])
    elif cmd == "/ip/hotspot/user/profile/print":
        finish([row(p) for p in STATE["profiles"]])
    elif cmd == "/ip/hotspot/user/add":
        STATE["users"].append({
            ".id": f"*{STATE['next_id']}",
            "name": params.get("name", "?"),
            "password": params.get("password", ""),
            "profile": params.get("profile", "default"),
            "uptime": "0s", "disabled": "false",
            "comment": params.get("comment", ""),
        })
        STATE["next_id"] += 1
        finish()
    elif cmd == "/ip/hotspot/user/remove":
        num = params.get("numbers", "")
        STATE["users"] = [u for u in STATE["users"] if u[".id"] != num]
        finish()
    else:
        finish()

    return logged_in


def client_thread(conn, addr):
    print(f"[+] connection from {addr}")
    logged_in = False
    try:
        while True:
            words = read_sentence(conn)
            if not words:
                continue
            logged_in = handle(words, conn, logged_in)
    except (ConnectionError, OSError):
        pass
    finally:
        conn.close()
        print(f"[-] disconnected {addr}")


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(8)
    print(f"RouterOS API simulator listening on {HOST}:{PORT}")
    print(f"login -> user={USER} password={PASSWORD}")
    while True:
        conn, addr = srv.accept()
        threading.Thread(target=client_thread, args=(conn, addr),
                         daemon=True).start()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
