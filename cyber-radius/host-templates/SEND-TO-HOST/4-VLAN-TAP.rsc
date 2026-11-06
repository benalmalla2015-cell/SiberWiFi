# cyber-vlan-tap — paste on RB1100 (3 commands, additive)
# Listens for VLAN 99 tagged frames on the EXISTING bridge and lands
# them in the isolated cyber bridge. Untagged customer traffic untouched.
# IMPORTANT: if the customer's bridge is not named "bdge_hp", check its
# real name first with:   /interface bridge print

/interface vlan add name=cyber-v99 vlan-id=99 interface=bdge_hp comment=cyber
/interface bridge port add bridge=cyber interface=cyber-v99
/log info "cyber vlan99 tap installed"
