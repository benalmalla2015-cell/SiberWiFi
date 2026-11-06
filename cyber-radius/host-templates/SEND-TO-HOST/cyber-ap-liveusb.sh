#!/usr/bin/env bash
# =============================================================================
# cyber-ap-liveusb.sh — turn a Linux laptop (Ubuntu live USB or install)
# into a CyberNet WPA2-Enterprise access point for the field test.
#
#   phone -> hostapd (this laptop, wlan0) -> RADIUS 200.141.8.191 -> accept
#   clients get 10.99.0.x via dnsmasq, NAT out through eth0 (host LAN).
#
# ZERO changes to the host network — this laptop is just a NAT client
# with a second wireless interface. Nothing on the friend's gear is touched.
#
# Run:  sudo bash cyber-ap-liveusb.sh
# Stop: sudo bash cyber-ap-liveusb.sh --stop
# =============================================================================
set -euo pipefail

SECRET="__SECRET__"   # replaced by ops before handing over
RADIUS_IP="200.141.8.191"
SSID="CyberNet"
WLAN_IF="${WLAN_IF:-wlan0}"
WAN_IF="${WAN_IF:-eth0}"     # set WAN_IF=enp3s0 or whatever uplink iface
SUBNET="10.99.0"

if [[ "${1:-}" == "--stop" ]]; then
    pkill hostapd 2>/dev/null || true
    pkill dnsmasq 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s ${SUBNET}.0/24 -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
    sysctl -w net.ipv4.ip_forward=0 >/dev/null
    nmcli device set "$WLAN_IF" managed yes 2>/dev/null || true
    echo "cyber-ap stopped."
    exit 0
fi

apt-get update -qq
apt-get install -y -qq hostapd dnsmasq iw >/dev/null

# --- sanity: interface + AP-mode support
iw dev | grep -q "Interface $WLAN_IF" || { echo "!! $WLAN_IF not found: iw dev"; exit 1; }
iw list | grep -A10 "Supported interface modes" | grep -qw AP \
    || { echo "!! $WLAN_IF does not support AP mode — use a USB WiFi adapter"; exit 1; }

# keep NetworkManager off our radio
nmcli device set "$WLAN_IF" managed no 2>/dev/null || true
rfkill unblock all 2>/dev/null || true
ip link set "$WLAN_IF" up
ip addr flush dev "$WLAN_IF"
ip addr add ${SUBNET}.1/24 dev "$WLAN_IF"

# --- hostapd (real 802.1X NAS -> FreeRADIUS)
cat >/tmp/cyber-hostapd.conf <<EOF
interface=$WLAN_IF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
ieee8021x=1
eapol_version=2
wpa=2
wpa_key_mgmt=WPA-EAP
rsn_pairwise=CCMP
auth_server_addr=$RADIUS_IP
auth_server_port=1812
auth_server_shared_secret=$SECRET
acct_server_addr=$RADIUS_IP
acct_server_port=1813
acct_server_shared_secret=$SECRET
acct_server_interval=60
nas_identifier=liveusb-cyber-001
EOF

# --- DHCP+DNS for cyber clients
cat >/tmp/cyber-dnsmasq.conf <<EOF
interface=$WLAN_IF
bind-interfaces
dhcp-range=${SUBNET}.50,${SUBNET}.200,1h
dhcp-option=3,${SUBNET}.1
dhcp-option=6,8.8.8.8,1.1.1.1
EOF
dnsmasq -C /tmp/cyber-dnsmasq.conf

# --- NAT uplink
sysctl -w net.ipv4.ip_forward=1 >/dev/null
iptables -t nat -A POSTROUTING -s ${SUBNET}.0/24 -o "$WAN_IF" -j MASQUERADE

echo "============================================================"
echo " CyberNet AP is UP on $WLAN_IF  (uplink: $WAN_IF)"
echo " Connect the phone, watch hostapd scroll the EAP exchange."
echo " Ctrl-C to stop; then run: sudo bash $0 --stop"
echo "============================================================"
hostapd -dd -t /tmp/cyber-hostapd.conf
