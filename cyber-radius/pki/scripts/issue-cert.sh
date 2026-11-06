#!/usr/bin/env bash
# =============================================================================
# issue-cert.sh — issue an encrypted EAP-TLS client cert for a subscriber.
#
#   ./issue-cert.sh 74XXXXXXX [--days N] [--p12-pass PASS] [--force]
#
# Output (under pki/clients/<sub>/):
#   <sub>.crt   — subscriber certificate (PEM)
#   <sub>.key   — private key (PEM, unencrypted — embedded in the .p12)
#   <sub>.p12   — PKCS#12 bundle (cert + key + CA chain), export-encrypted
#
# The .p12 password is printed once — pass it to the app/backend over a
# secure channel; it is NOT stored on disk.
# =============================================================================
set -euo pipefail

# Git Bash (Windows dev) mangles openssl /C=YE/... subjects into paths —
# harmless no-op on Linux.
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:-*}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"
# Relative paths: native openssl.exe can't read /c/... MSYS paths.
CADIR="pki/ca"
CONF="pki/openssl-cyber.cnf"
CLIENTS="pki/clients"

DAYS=825
P12_PASS="${CYBER_P12_PASS:-}"
FORCE=0
SUB=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--days)     DAYS="$2"; shift 2 ;;
		--p12-pass) P12_PASS="$2"; shift 2 ;;
		--force)    FORCE=1; shift ;;
		-*)         echo "unknown flag: $1" >&2; exit 2 ;;
		*)          SUB="$1"; shift ;;
	esac
done

[[ "$SUB" =~ ^74[0-9]{7}$ ]] || {
	echo "usage: $0 74XXXXXXX  (subscriber number: 9 digits starting with 74)" >&2
	exit 2
}
command -v openssl >/dev/null || { echo "openssl not found" >&2; exit 1; }
[[ -f "$CADIR/private/ca.key" ]] || {
	echo "CA not initialized — run init-ca.sh first" >&2; exit 1
}

OUT="$CLIENTS/$SUB"

# Refuse to silently re-issue a live cert: check index.txt for a valid
# (non-revoked) entry with this CN.
if grep -qE "^V	[0-9]+Z		[0-9A-Fa-f]+	unknown	/C=YE/O=CyberNet/CN=$SUB\$" "$CADIR/index.txt" 2>/dev/null \
   && [[ $FORCE -eq 0 ]]; then
	echo "$SUB already has a valid certificate — revoke it first, or pass --force" >&2
	exit 1
fi
[[ $FORCE -eq 1 ]] && rm -rf "$OUT"
mkdir -p "$OUT"

SUBJ="/C=YE/O=CyberNet/CN=$SUB"

echo "==> [$SUB] generating client key"
openssl genrsa -out "$OUT/$SUB.key" 2048
chmod 600 "$OUT/$SUB.key"

echo "==> [$SUB] CSR"
openssl req -new -config "$CONF" -key "$OUT/$SUB.key" \
	-out "$OUT/$SUB.csr" -subj "$SUBJ"

echo "==> [$SUB] signing with CyberNet CA (${DAYS}d)"
openssl ca -batch -config "$CONF" -extensions client_cert \
	-in "$OUT/$SUB.csr" -out "$OUT/$SUB.crt" -days "$DAYS" \
	-subj "$SUBJ"
rm -f "$OUT/$SUB.csr"

# Export password: from arg/env, else the documented pilot convention
# "cyber<sim>" that GET /cyber/identity/certificate serves to the
# device-bound app. Override with --p12-pass for production issues.
if [[ -z "$P12_PASS" ]]; then
	P12_PASS="cyber${SUB}"
fi

# Android compatibility: the platform KeyStore rejects OpenSSL 3's
# default PBKDF2 PKCS#12 protection (NoSuchAlgorithmException for OID
# 1.2.840.113549.1.5.12). PBE-SHA1-3DES for both bags + a SHA-1 MAC is
# the widely supported profile Android can import.
echo "==> [$SUB] exporting .p12 (cert + key + CA chain, Android profile)"
openssl pkcs12 -export \
	-inkey "$OUT/$SUB.key" -in "$OUT/$SUB.crt" \
	-certfile "$CADIR/ca.crt" \
	-name "CyberNet-$SUB" \
	-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
	-out "$OUT/$SUB.p12" -passout "pass:$P12_PASS"
chmod 600 "$OUT/$SUB.p12"

SERIAL="$(openssl x509 -in "$OUT/$SUB.crt" -noout -serial | cut -d= -f2)"

cat <<EOF

Issued for subscriber $SUB
  cert   : $OUT/$SUB.crt
  key    : $OUT/$SUB.key
  bundle : $OUT/$SUB.p12
  serial : $SERIAL
  p12 password: $P12_PASS   <-- deliver once, never stored
EOF
