#!/bin/bash

# Script Name: cert_rsa_client.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 3.0.0

# Description:
# This script creates an RSA client certificate, signed by the intermediate
# certificate authority. It also creates the chain bundle.
# The work is done by cert.sh in the same folder. This script starts it with
# --algo rsa --role client and passes all other options on.

# Usage: ./cert_rsa_client.sh [--fqdn <fqdn>] [--www] [--reuse-key] [-h|--help]
#
# Options:
#  --fqdn <fqdn> Run without questions for this FQDN. The Common Name is
#                set to the FQDN, so it is not asked a second time.
#  --www         Also add www.<fqdn> to the subject alternative names.
#  --reuse-key   Reuse the existing private key of this FQDN instead of
#                generating a new one. The key must exist.
#  -h, --help    Show this help.
#
# Without options the script asks for the details.

# Notes:
# - The certificates are for a homelab and for testing.
# - Certificates are stored under $HOME/tls.
# - A certificate covers the FQDN. Use --www to add www.<fqdn>.

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

for argument in "$@"; do
  case "$argument" in
  -h | --help)
    sed -n '/^# Usage:/,/^$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  esac
done

exec bash "$script_dir/cert.sh" --algo rsa --role client "$@"
