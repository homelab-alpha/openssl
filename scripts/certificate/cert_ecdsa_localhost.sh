#!/bin/bash

# Script Name: cert_ecdsa_localhost.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 3.0.0

# Description:
# This script creates an ECDSA server certificate for localhost, signed by the
# intermediate certificate authority. It also creates the chain bundle and a
# bundle for HAProxy.
# The work is done by cert.sh in the same folder. This script starts it with
# --algo ecdsa --role server --localhost and passes all other options on.

# Usage: ./cert_ecdsa_localhost.sh [--non-interactive] [--reuse-key] [-h|--help]
#
# Options:
#  --non-interactive Kept for older commands. The script never asks a
#                    question.
#  --reuse-key       Reuse the existing private key instead of generating a
#                    new one. The key must exist.
#  -h, --help        Show this help.
#
# The Common Name is localhost.

# Notes:
# - The certificates are for a homelab and for testing.
# - Certificates are stored under $HOME/tls.
# - The certificate covers localhost, *.localhost, and 127.0.0.1.

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

for argument in "$@"; do
  case "$argument" in
  -h | --help)
    sed -n '/^# Usage:/,/^$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  esac
done

exec bash "$script_dir/cert.sh" --algo ecdsa --role server --localhost "$@"
