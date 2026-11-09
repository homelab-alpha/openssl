#!/bin/bash

# Script Name: revoke_ssl_certificates.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-09T10:00:00+01:00
# Version: 1.0.0

# Description:
# Deprecated. This script is renamed to revoke_tls_certificates.sh.
# It only starts the new script with the same arguments, so old aliases, cron
# jobs, and systemd units keep working. It will be removed in a future major
# version.

# Usage: ./revoke_ssl_certificates.sh [arguments of revoke_tls_certificates.sh]

new_script="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/revoke_tls_certificates.sh"

echo "Warning: revoke_ssl_certificates.sh is renamed to revoke_tls_certificates.sh. Use the new name." >&2

exec "$new_script" "$@"
