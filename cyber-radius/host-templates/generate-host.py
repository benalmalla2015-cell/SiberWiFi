#!/usr/bin/env python3
"""
generate-host.py — CyberNet host .rsc generator (CYB-02)

Renders host.rsc.tmpl with a unique per-host RADIUS secret and a fresh
WireGuard keypair, then emits:
    generated/<host-id>.rsc          -> paste on the host MikroTik
    generated/<host-id>.server.conf  -> WireGuard peer + FreeRADIUS client
                                      blocks to install on the VPS
    hosts.json                       -> allocation registry (IPs, keys ref)

Usage (defaults come from registry 'network' section):
    py generate-host.py --host-id almalla-001 \
        --endpoint vpn.example.com --server-pubkey "<server-wg-pubkey>"

First run also needs the server WireGuard public key; afterwards the
registry remembers endpoint/pubkey so new hosts need only --host-id.
"""

import argparse
import base64
import ipaddress
import json
import secrets
import string
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "host.rsc.tmpl"
REGISTRY = HERE / "hosts.json"
OUTDIR = HERE / "generated"

P = 2**255 - 19
A24 = 121665


def _x25519_pure(priv: bytes) -> bytes:
    """RFC 7748 X25519(priv, basepoint=9) — pure-python fallback."""
    k = bytearray(priv)
    k[0] &= 248
    k[31] &= 127
    k[31] |= 64
    k_int = int.from_bytes(k, "little")
    x1, x2, z2, x3, z3, swap = 9, 1, 0, 9, 1, 0
    for t in reversed(range(255)):
        kt = (k_int >> t) & 1
        swap ^= kt
        if swap:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = kt
        a = (x2 + z2) % P
        aa = a * a % P
        b = (x2 - z2) % P
        bb = b * b % P
        e = (aa - bb) % P
        c = (x3 + z3) % P
        d = (x3 - z3) % P
        da = d * a % P
        cb = c * b % P
        x3 = (da + cb) ** 2 % P
        z3 = x1 * (da - cb) ** 2 % P
        x2 = aa * bb % P
        z2 = e * (aa + A24 * e) % P
    if swap:
        x2, x3, z2, z3 = x3, x2, z3, z2
    return (x2 * pow(z2, P - 2, P) % P).to_bytes(32, "little")


def gen_wg_keypair() -> tuple[str, str]:
    """Return (private_b64, public_b64) Curve25519 keys, wg-compatible."""
    priv = secrets.token_bytes(32)
    try:
        from cryptography.hazmat.primitives.asymmetric.x25519 import (
            X25519PrivateKey,
        )
        from cryptography.hazmat.primitives import serialization

        pub = (
            X25519PrivateKey.from_private_bytes(priv)
            .public_key()
            .public_bytes(
                serialization.Encoding.Raw, serialization.PublicFormat.Raw
            )
        )
    except ImportError:
        pub = _x25519_pure(priv)
    return base64.b64encode(priv).decode(), base64.b64encode(pub).decode()


def load_registry() -> dict:
    if REGISTRY.exists():
        return json.loads(REGISTRY.read_text(encoding="utf-8"))
    return {
        "network": {
            "wg_net": "10.66.0.0/24",
            "server_wg_ip": "10.66.0.1",
            "wg_endpoint": None,
            "wg_endpoint_port": 51820,
            "wg_listen_port": 13231,
            "server_pubkey": None,
            "ssid": "CyberNet",
            "lan_base": "10.77.0.0/16",
            "radius_auth_port": 1812,
            "radius_acct_port": 1813,
            "coa_port": 3799,
        },
        "hosts": {},
    }


def save_registry(reg: dict) -> None:
    REGISTRY.write_text(
        json.dumps(reg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def allocate(reg: dict, host_id: str) -> tuple[str, ipaddress.IPv4Network]:
    """Assign host tunnel IP and client LAN /24, stable across re-runs."""
    net = reg["network"]
    wg_net = ipaddress.ip_network(net["wg_net"])
    lan_base = ipaddress.ip_network(net["lan_base"])
    hosts = reg["hosts"]

    if host_id in hosts:
        h = hosts[host_id]
        return h["wg_ip"], ipaddress.ip_network(h["lan_subnet"])

    used_wg = {ipaddress.ip_address(h["wg_ip"]) for h in hosts.values()}
    used_lan = {ipaddress.ip_network(h["lan_subnet"]) for h in hosts.values()}

    wg_ip = next(
        ip for ip in wg_net.hosts()
        if ip != ipaddress.ip_address(net["server_wg_ip"]) and ip not in used_wg
    )
    lan = next(
        s for s in lan_base.subnets(new_prefix=24) if s not in used_lan
    )
    return str(wg_ip), lan


def render(template: str, values: dict) -> str:
    out = template
    for k, v in values.items():
        out = out.replace("{{" + k + "}}", str(v))
    leftovers = [t for t in out.split("{{")[1:] if "}}" in t]
    if leftovers:
        raise SystemExit(
            "unresolved placeholders: "
            + ", ".join("{{" + t.split("}}")[0] + "}}" for t in leftovers)
        )
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host-id", required=True,
                    help="unique host slug, e.g. almalla-001")
    ap.add_argument("--endpoint", help="server public IP/DNS for WireGuard")
    ap.add_argument("--server-pubkey", help="server WireGuard public key (b64)")
    ap.add_argument("--wg-port", type=int, help="server WireGuard port")
    ap.add_argument("--force", action="store_true",
                    help="re-generate secrets even if host exists")
    args = ap.parse_args()

    reg = load_registry()
    net = reg["network"]

    if args.endpoint:
        net["wg_endpoint"] = args.endpoint
    if args.server_pubkey:
        net["server_pubkey"] = args.server_pubkey
    if args.wg_port:
        net["wg_endpoint_port"] = args.wg_port

    missing = [k for k in ("wg_endpoint", "server_pubkey") if not net.get(k)]
    if missing:
        raise SystemExit(
            f"missing {missing}: pass --endpoint and --server-pubkey "
            "(once — they are stored in hosts.json afterwards)"
        )

    host_id = args.host_id
    existing = reg["hosts"].get(host_id)
    if existing and not args.force:
        print(f"{host_id}: already generated, reusing stored allocation "
              f"(use --force to rotate secrets)")

    wg_ip, lan = allocate(reg, host_id)
    wg_ip_cidr = f"{wg_ip}/32"

    if existing and not args.force:
        # Secrets are emitted into the .rsc exactly once; regenerating
        # requires --force so the secret stays unique & unguessable.
        raise SystemExit(
            f"{host_id}: .rsc already generated. The RADIUS secret is only "
            f"ever emitted once; re-run with --force to rotate credentials."
        )

    alphabet = string.ascii_letters + string.digits
    host_secret = "".join(secrets.choice(alphabet) for _ in range(40))
    wg_priv, wg_pub = gen_wg_keypair()

    values = {
        "HOST_ID": host_id,
        "GENERATED_AT": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "SSID": net["ssid"],
        "CYBER_SUBNET": str(lan),
        "CYBER_GW_CIDR": f"{lan.network_address + 1}/24",
        "CYBER_POOL": f"{lan.network_address + 10}-{lan.network_address + 250}",
        "RADIUS_IP": net["server_wg_ip"],
        "RADIUS_AUTH_PORT": net["radius_auth_port"],
        "RADIUS_ACCT_PORT": net["radius_acct_port"],
        "COA_PORT": net["coa_port"],
        "HOST_SECRET": host_secret,
        "WG_PRIVATE_KEY": wg_priv,
        "WG_SERVER_PUBKEY": net["server_pubkey"],
        "WG_ENDPOINT": net["wg_endpoint"],
        "WG_ENDPOINT_PORT": net["wg_endpoint_port"],
        "WG_LISTEN_PORT": net["wg_listen_port"],
        "WG_HOST_IP_CIDR": wg_ip_cidr,
        "WG_NET": net["wg_net"],
    }

    rsc = render(TEMPLATE.read_text(encoding="utf-8"), values)

    OUTDIR.mkdir(exist_ok=True)
    rsc_path = OUTDIR / f"{host_id}.rsc"
    rsc_path.write_text(rsc, encoding="utf-8")

    srv = (
        f"# ---- {host_id} — install on the CyberNet VPS ----\n"
        f"# 1) WireGuard peer (add under [Interface] or /interface wireguard peers)\n"
        f"[Peer]\n"
        f"PublicKey  = {wg_pub}\n"
        f"AllowedIPs = {wg_ip}/32\n"
        f"\n"
        f"# 2) FreeRADIUS client -> append to clients.conf\n"
        f"client {host_id} {{\n"
        f"    ipaddr   = {wg_ip}\n"
        f"    secret   = {host_secret}\n"
        f"    nas_type = mikrotik\n"
        f"    require_message_authenticator = yes\n"
        f"}}\n"
        f"# client LAN behind this NAS: {lan} (info only, not routed via wg)\n"
    )
    srv_path = OUTDIR / f"{host_id}.server.conf"
    srv_path.write_text(srv, encoding="utf-8")

    reg["hosts"][host_id] = {
        "wg_ip": wg_ip,
        "lan_subnet": str(lan),
        "wg_pubkey": wg_pub,
        "radius_secret_hint": host_secret[:4] + "..." + host_secret[-4:],
        "created": values["GENERATED_AT"],
    }
    save_registry(reg)

    print(f"host      : {host_id}")
    print(f"rsc       : {rsc_path}")
    print(f"server    : {srv_path}")
    print(f"wg host ip: {wg_ip_cidr}  pub: {wg_pub}")
    print(f"client LAN: {lan}  (bridge {lan.network_address + 1})")
    print(f"registry  : {REGISTRY}")


if __name__ == "__main__":
    sys.exit(main())
