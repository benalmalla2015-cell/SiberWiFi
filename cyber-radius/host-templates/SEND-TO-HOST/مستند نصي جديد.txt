# cyber-key - paste AFTER the main file. 3 lines only.
# This is the ONLY file containing the upstream key. Keep it off
# chat/email attachments; hand it to the host on a separate channel.
/radius add service=wireless address=200.141.8.191 secret=__ALMALLA_V6_001_RADIUS_SECRET__ timeout=2s comment="cyber-upstream"
/log info "cyber key installed"
