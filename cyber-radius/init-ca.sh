#!/usr/bin/env bash
# =============================================================================
# init-ca.sh — one-time CyberNet private CA bootstrap (run ON the VPS).
#
# Creates pki/ca/ (root key + cert + db + CRL), issues the RADIUS server
# certificate, generates DH params, and stages everything FreeRADIUS needs
# into raddb/certs/.  Safe to re-run: refuses to overwrite an existing CA
# unless --force is passed.
#
# Usage:  ./init-ca.sh [--force] [--ca-days N] [--server-days N]
# =============================================================================
set -euo pipefail

# Git Bash (Windows dev) mangles openssl /C=YE/... subjects into paths —
# harmless no-op on Linux.
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:-*}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
# Relative paths from here on: native openssl.exe can't read /c/... MSYS
# paths, and openssl-cyber.cnf declares `dir = ./pki/ca` relative to cwd.
CADIR="pki/ca"
CONF="pki/openssl-cyber.cnf"
CERTS_OUT="raddb/certs"

CA_DAYS=3650      # 10y root
SERVER_DAYS=825   # ~27m server cert
FORCE=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--force)       FORCE=1; shift ;;
		--ca-days)     CA_DAYS="$2"; shift 2 ;;
		--server-days) SERVER_DAYS="$2"; shift 2 ;;
		*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
done

command -v openssl >/dev/null || { echo "openssl not found" >&2; exit 1; }

if [[ -f "$CADIR/private/ca.key" && $FORCE -eq 0 ]]; then
	echo "CA already exists at $HERE/pki/ca (use --force to rebuild — this revokes every issued cert)"
	exit 1
fi

echo "==> creating CyberNet CA layout under $HERE/pki/ca"
mkdir -p "$CADIR/private" "$CADIR/newcerts" "pki/clients" "$CERTS_OUT"
chmod 700 "$CADIR/private"

# Fresh CA db.
: > "$CADIR/index.txt"
echo 1000 > "$CADIR/serial"
echo 1000 > "$CADIR/crlnumber"

echo "==> generating root CA key (RSA 4096) — keep this file offline-safe"
openssl genrsa -out "$CADIR/private/ca.key" 4096
chmod 600 "$CADIR/private/ca.key"

echo "==> self-signing root CA cert (${CA_DAYS}d)"
openssl req -new -x509 -config "$CONF" -extensions ca_cert \
	-key "$CADIR/private/ca.key" \
	-out "$CADIR/ca.crt" -days "$CA_DAYS" \
	-subj "/C=YE/O=CyberNet/CN=CyberNet Root CA"
chmod 644 "$CADIR/ca.crt"

echo "==> issuing RADIUS server cert (CN=radius.cybernet.local, ${SERVER_DAYS}d)"
openssl genrsa -out "$CADIR/private/server.key" 3072
chmod 600 "$CADIR/private/server.key"
openssl req -new -config "$CONF" \
	-key "$CADIR/private/server.key" \
	-out "$CADIR/server.csr" \
	-subj "/C=YE/O=CyberNet/CN=radius.cybernet.local"
openssl ca -batch -config "$CONF" -extensions server_cert \
	-in "$CADIR/server.csr" -out "$CADIR/server.crt" -days "$SERVER_DAYS" \
	-subj "/C=YE/O=CyberNet/CN=radius.cybernet.local"
rm -f "$CADIR/server.csr"

echo "==> generating DH params (2048-bit — slow on small VPS, one-time)"
openssl dhparam -out "$CADIR/dh.pem" 2048

echo "==> issuing empty CRL"
openssl ca -config "$CONF" -gencrl -out "$CADIR/crl.pem"

echo "==> staging raddb/certs/ for the container"
cp "$CADIR/private/server.key" "$CERTS_OUT/server.key"
cp "$CADIR/server.crt"         "$CERTS_OUT/server.crt"
cp "$CADIR/ca.crt"             "$CERTS_OUT/ca.crt"
cp "$CADIR/dh.pem"             "$CERTS_OUT/dh"
cp "$CADIR/crl.pem"            "$CERTS_OUT/crl.pem"
chmod 600 "$CERTS_OUT/server.key"
chmod 644 "$CERTS_OUT/server.crt" "$CERTS_OUT/ca.crt" "$CERTS_OUT/dh" "$CERTS_OUT/crl.pem"

# Hash the CA dir so OpenSSL can find the CRL for check_crl.
# (portable stand-in for `openssl rehash`, which is missing on some builds)
H="$(openssl x509 -in "$CERTS_OUT/ca.crt" -noout -hash)"
cp "$CERTS_OUT/ca.crt" "$CERTS_OUT/$H.0"
H="$(openssl crl -in "$CERTS_OUT/crl.pem" -noout -hash)"
cp "$CERTS_OUT/crl.pem" "$CERTS_OUT/$H.r0"

echo
echo "Done. CA fingerprint:"
openssl x509 -in "$CADIR/ca.crt" -noout -fingerprint -sha256
echo
echo "Next: cp .env.example .env && fill CYBER_ENGINE_* && docker compose up -d"
