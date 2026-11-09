#!/bin/bash

# Script Name: ssl_certificate_status.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-09T10:00:00+01:00
# Version: 1.0.0

# Description:
# Deprecated. This script is renamed to tls_certificate_status.sh.
# It only starts the new script with the same arguments, so old aliases, cron
# jobs, and systemd units keep working. It will be removed in a future major
# version.

# Usage: ./ssl_certificate_status.sh [arguments of tls_certificate_status.sh]

new_script="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tls_certificate_status.sh"

echo "Warning: ssl_certificate_status.sh is renamed to tls_certificate_status.sh. Use the new name." >&2

exec "$new_script" "$@"
