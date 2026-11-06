#!/usr/bin/env bash
# =============================================================================
# revoke-cert.sh — revoke a subscriber cert and republish the CRL.
#
#   ./revoke-cert.sh 74XXXXXXX
#
# Steps: mark the cert revoked in index.txt -> regenerate crl.pem ->
# refresh raddb/certs/ + openssl rehash -> FreeRADIUS rejects the cert on
# its next auth attempt (check_crl = yes in mods-enabled/eap).
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
CERTS_OUT="raddb/certs"

SUB="${1:-}"
[[ "$SUB" =~ ^74[0-9]{7}$ ]] || {
	echo "usage: $0 74XXXXXXX" >&2; exit 2
}
command -v openssl >/dev/null || { echo "openssl not found" >&2; exit 1; }
[[ -f "$CADIR/private/ca.key" ]] || { echo "CA not initialized" >&2; exit 1; }

# Locate the cert file: prefer pki/clients/<sub>/, fall back to index.txt serial.
CRT="pki/clients/$SUB/$SUB.crt"
if [[ ! -f "$CRT" ]]; then
	LINE="$(grep -E "^V	.*	/C=YE/O=CyberNet/CN=$SUB\$" "$CADIR/index.txt" | tail -n1 || true)"
	[[ -n "$LINE" ]] || { echo "no valid certificate found for $SUB" >&2; exit 1; }
	SERIAL="$(awk -F'\t' '{print $4}' <<<"$LINE")"
	CRT="$(find "$CADIR/newcerts" -name "${SERIAL}.pem" -o -name "${SERIAL}.crt" | head -n1 || true)"
	[[ -n "$CRT" && -f "$CRT" ]] || {
		echo "cert file for $SUB (serial $SERIAL) not found under $CADIR/newcerts" >&2
		exit 1
	}
fi

# Already revoked?
if grep -qE "^R	.*	/C=YE/O=CyberNet/CN=$SUB\$" "$CADIR/index.txt"; then
	echo "$SUB is already revoked"
else
	echo "==> revoking $SUB"
	openssl ca -config "$CONF" -revoke "$CRT" -crl_reason keyCompromise
fi

echo "==> regenerating CRL"
openssl ca -config "$CONF" -gencrl -out "$CADIR/crl.pem"

echo "==> refreshing raddb/certs/"
cp "$CADIR/crl.pem" "$CERTS_OUT/crl.pem"
# Republish the hashed CRL the way `openssl rehash` would (check_crl
# resolves CRLs by issuer hash in ca_path).
H="$(openssl crl -in "$CERTS_OUT/crl.pem" -noout -hash)"
cp "$CERTS_OUT/crl.pem" "$CERTS_OUT/$H.r0"

cat <<EOF

Revoked $SUB — CRL republished at $CERTS_OUT/crl.pem
Reload radius to pick it up immediately:
  docker compose restart freeradius
(otherwise the next TLS handshake after CRL refresh is still honored —
 the cert is checked against the file on every auth)
EOF
