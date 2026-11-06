# cyber-test-ap — paste on the MikroTik ACCESS POINT device (NOT on RB1100)
# Requirements: ether1 uplinked to a free port on RB1100, wlan radio exists.
# Additive only: bridge cyber-ap + wlan1 SSID CyberNet -> EAP passthrough.
# After this file, paste the KEY file (2-KEY) here too (the same /radius line).

/interface bridge add name=cyber-ap
/interface bridge port add bridge=cyber-ap interface=ether1
/interface bridge port add bridge=cyber-ap interface=wlan1

/interface wireless security-profiles add name=cyber-sec mode=dynamic-keys \
    authentication-types=wpa2-eap unicast-ciphers=aes-ccm group-ciphers=aes-ccm \
    eap-methods=passthrough supplicant-identity=""

/interface wireless set wlan1 ssid=CyberNet mode=ap-bridge band=2ghz-b/g/n \
    security-profile=cyber-sec disabled=no

# management IP inside the cyber subnet so this AP can reach the RADIUS server
/ip dhcp-client add interface=cyber-ap disabled=no comment=cyber
