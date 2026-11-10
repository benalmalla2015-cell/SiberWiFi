# CyberNet EAP-TLS — Live Field Test State
Date: 2026-11-09 (paused mid-test — resume in the evening at the host site)

## Confirmed working

- KT-9200TI Pro broadcasts **CyberNet** as a separate VAP (BSSID `06:07:89:b1:01:ad`)
  alongside production SSIDs (HajWaLa Net 217 / +2 / 5G — all untouched, `Encryption: None`).
- CyberNet VAP runs **WPA2-802.1X (TKIP+CCMP)** — confirmed in LuCI Wireless Overview.
- LuCI RADIUS config: Auth `200.141.8.191:1812` + Acct `200.141.8.191:1813`,
  secret = real 40-char value (verified identical to `secure/ACTIVE-SECRETS.local.txt`).
- **VPS FreeRADIUS is alive**: synthetic Access-Request from the host WAN
  (`209.198.151.94`) with the real secret → `Access-Reject` in seconds.
  Wrong secret → silent drop. Proves server, port, secret and WAN path all good.
- Flutter app EAP-TLS suggestion **installed and approved** on the phone
  (nid 86/88, `security: eap`) — embeds `.p12` + CA + domain `radius.cybernet.local`
  fetched from `GET /api/cyber/identity/certificate` (files provisioned at
  `backend/storage/app/cyber/certs/`).
- Backend (local SQLite) serves subscriber `741582498` bound to device
  `and-becb7e7902029a2f`; daily package activated; balance 4,800 YER.

## Open failure — CONFIRMED root cause (evening session)

Phone cycle: `EAP-STARTED` → 30 s silence → `DISCONNECTED reason=23` → `AUTH_FAILED` → retry.
The AP gets **no RADIUS reply**. Since secret+server are proven good:

**KT had no route to the internet.** LuCI Diagnostics ping `200.141.8.191` →
`sendto: Network unreachable`. Root cause found: the device's real upstream
segment serves `192.168.50.0/24` (gateway `192.168.50.1` — the MikroTik LAN),
while `lan` was `10.0.0.22/16` with gateway `10.0.0.1` (which does not exist
on that segment — `10.0.0.1` is the MikroTik's WAN/exit address, not a LAN IP).

**Fix applied**: added a second interface `cyberwan` on the same `br-lan`
bridge — `192.168.50.222/24`, gateway + DNS `192.168.50.1` — keeping
`10.0.0.22` management untouched. Pending verification of
`Ping 200.141.8.191` from the KT after apply.

## Resume checklist (next visit)

1. **Phone cleanup**: WiFi settings → CyberNet → **Forget** the manually-created
   WPA_EAP profile (nid 85, no client cert — was created by hand and always fails).
   Keep the app-installed suggestion.
2. **Verify KT internet**: LuCI → Network → **Diagnostics** → Ping → `200.141.8.191`
   must reply now that `cyberwan` (192.168.50.222/24 gw 192.168.50.1) is applied.
   If still unreachable → LuCI → Status → Routes — check whether the
   192.168.50.x segment really is on-link on br-lan; confirm the MikroTik
   answers `Ping 192.168.50.1` from the KT.
3. Phone retries EAP automatically every ~30 s after each failure — once the AP
   reaches the VPS expect `EAP-SUCCESS` → `COMPLETED` → DHCP IP on `lan`.
4. After connect: verify IP + internet through CyberNet, then check FreeRADIUS
   Access-Accept + accounting packets arriving.

## Notes

- `require_message_authenticator = yes` in clients.conf — hostapd sends it, fine.
- `126:s:Operator` attr still in LuCI — harmless, remove when convenient.
- VPS SSH key `~/.ssh/saiberwifi_deploy` is **corrupted** (pubkey blob only, no
  private key) — server-side log access unavailable; needs re-issuing next deploy.
- Backend runs locally via `php artisan serve` + `adb reverse` for the test bench —
  production app needs the API hosted on the VPS/domain to work in the field.
