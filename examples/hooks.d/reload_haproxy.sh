#!/bin/bash

# Script Name: reload_haproxy.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-09T10:00:00+01:00
# Version: 1.1.0

# Description:
# Example hook for renew_tls_certificates.sh. It reloads HAProxy after a
# certificate was renewed. The hook is disabled by default, because the copy
# in ~/tls/hooks.d/ is not executable. The file in the repository is executable
# (the linter requires that), so copy it with install -m 644, not with cp.
#
# To enable it:
#   mkdir -p ~/tls/hooks.d
#   install -m 644 ~/openssl/examples/hooks.d/reload_haproxy.sh ~/tls/hooks.d/
#   chmod +x ~/tls/hooks.d/reload_haproxy.sh
#
# Usage: reload_haproxy.sh <fqdn> <certificate> <chain_bundle> <key> <haproxy_bundle>
# The renewal script passes these arguments. The HAProxy bundle is an empty
# string for client certificates.

# Notes:
# - Adjust the paths and the service name to your system.
# - HAProxy must use the renewed bundle ($HOME/tls/certs/certificates/<fqdn>_haproxy.pem),
#   for example through a crt line in haproxy.cfg.
# - Reloading a service usually needs root. Run the renewal as a user that is
#   allowed to do that, or change the command (for example a sudoers rule for
#   this one command).
# - The certificates are for a homelab and for testing.

fqdn="$1"
haproxy_bundle="$5"

# Client certificates have no HAProxy bundle
if [[ -z "$haproxy_bundle" ]]; then
  exit 0
fi

# Check the configuration before the reload, so a mistake does not stop HAProxy
haproxy -c -f /etc/haproxy/haproxy.cfg || exit 1

systemctl reload haproxy || exit 1
echo "HAProxy reloaded for ${fqdn}."
