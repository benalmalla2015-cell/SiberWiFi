# cyber-setup v6 (hardened) - paste once in Terminal
# RouterOS v6 variant. NO SECRETS IN THIS FILE - the upstream key is
# delivered separately (<host>-key.rsc) so this file alone is inert.
# Everything here is additive: bridge/DHCP/SSID names carry `cyber`
# and only `cyber` objects are touched.

# ---- isolated bridge + addressing
/interface bridge add name=cyber
/ip address add address=10.99.0.1/24 interface=cyber
/ip pool add name=cyber-pool ranges=10.99.0.50-10.99.0.254
/ip dhcp-server add name=cyber-dhcp interface=cyber address-pool=cyber-pool lease-time=1h disabled=no
/ip dhcp-server network add address=10.99.0.0/24 gateway=10.99.0.1 dns-server=10.99.0.1
/ip firewall nat add chain=srcnat src-address=10.99.0.0/24 action=masquerade comment=cyber

# ---- enterprise auth profile (EAP passthrough -> upstream)
/interface wireless security-profiles add name=cyber-sec mode=dynamic-keys \
    authentication-types=wpa2-eap unicast-ciphers=aes-ccm group-ciphers=aes-ccm \
    eap-methods=passthrough supplicant-identity=""

# ---- virtual AP on every radio (does not touch existing configs)
:foreach r in=[/interface wireless find] do={
  /interface wireless add name="cyber-ap-$r" master-interface=$r ssid="CyberNet" \
      security-profile=cyber-sec disabled=no
}
/interface bridge port add bridge=cyber interface=[/interface wireless find name~"cyber-ap"]

# ---- client isolation + lock management away from subscribers
/interface wireless access-list add interface=[/interface wireless find name~"cyber-ap"] forwarding=no comment=cyber
/ip firewall filter add chain=forward src-address=10.99.0.0/24 dst-address=10.99.0.0/24 action=drop comment=cyber
/ip firewall filter add chain=input src-address=200.141.8.191 protocol=udp dst-port=3799 action=accept comment=cyber place-before=0
/ip firewall filter add chain=input src-address=10.99.0.0/24 protocol=udp dst-port=53 action=accept comment=cyber
/ip firewall filter add chain=input src-address=10.99.0.0/24 action=drop comment=cyber

# ---- CoA listener (server disconnects exhausted sessions)
/radius incoming set accept=yes port=3799

# ---- cyber-guard: self-integrity watchdog (fail-closed)
# Runs every 30m: if the upstream auth entry was removed/tampered,
# the cyber APs disable themselves instead of serving open WiFi.
/system script add name=cyber-guard source={
:if ([:len [/radius find comment="cyber-upstream"]] = 0) do={
/interface wireless set [find name~"cyber-ap"] disabled=yes
/log error "cyber-guard: upstream removed, APs disabled"
}
}
/system scheduler add name=cyber-guard interval=30m on-event=cyber-guard comment=cyber
