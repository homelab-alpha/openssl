#!/bin/bash

# Script Name: ssl_directory_setup.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-09T10:00:00+01:00
# Version: 1.0.0

# Description:
# Deprecated. This script is renamed to tls_directory_setup.sh.
# It only starts the new script with the same arguments, so old aliases, cron
# jobs, and systemd units keep working. It will be removed in a future major
# version.

# Usage: ./ssl_directory_setup.sh [arguments of tls_directory_setup.sh]

new_script="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tls_directory_setup.sh"

echo "Warning: ssl_directory_setup.sh is renamed to tls_directory_setup.sh. Use the new name." >&2

exec "$new_script" "$@"
