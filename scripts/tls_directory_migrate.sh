#!/bin/bash

# Script Name: tls_directory_migrate.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 1.1.0

# Description:
# This script moves the old directory $HOME/ssl to $HOME/tls and leaves a
# symbolic link $HOME/ssl -> tls behind, so old paths (cron jobs, systemd units,
# hooks, and HAProxy or nginx configuration) keep working. It also changes the
# path $HOME/ssl in the OpenSSL configuration files in $HOME/tls/openssl.cnf to
# $HOME/tls. Each changed file is saved first with the extension .pre-tls.
#
# The script does not delete any file and does not change a certificate, a key,
# or the database. Run it once. A second run does nothing.

# Usage: ./tls_directory_migrate.sh [--dry-run] [-h|--help]
#
# Options:
#  --dry-run      Show what would happen. Nothing is changed.
#  -h, --help     Show this help.

# Exit codes:
#  0  The directory was moved, or there is nothing to move.
#  1  The move failed.
#  2  Wrong usage, or both $HOME/ssl and $HOME/tls exist as directories.

# Notes:
# The certificates are for a homelab and for testing.
# Remove the symbolic link $HOME/ssl yourself when nothing uses the old path.

# Stop script on error. The functions below return a status on purpose, and
# the callers decide what a failure means.
set -Eeuo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh" || exit 2

# Function to show the usage (from the header of this script)
show_help() {
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# Define paths
old_dir="$HOME/ssl"
new_dir="$HOME/tls"

# Parse the arguments
dry_run=false
while [ $# -gt 0 ]; do
  case "$1" in
  --dry-run)
    dry_run=true
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    print_error "Unknown option: $1"
    exit 2
    ;;
  esac
done

# Decide what to do
if [ -L "$old_dir" ]; then
  echo "Nothing to do: $old_dir is already a symbolic link."
  exit 0
fi

if [ ! -d "$old_dir" ]; then
  echo "Nothing to do: $old_dir does not exist."
  exit 0
fi

if [ -e "$new_dir" ]; then
  print_error "Both $old_dir and $new_dir exist. Check them and move or remove one yourself."
  exit 2
fi

# List the configuration files that contain the old path
config_files=()
for file in "$old_dir"/openssl.cnf/*.cnf; do
  [ -f "$file" ] || continue
  if grep -q 'HOME/ssl' "$file"; then
    config_files+=("$file")
  fi
done

print_cyan "=== Migration plan ==="
echo "Move:   $old_dir -> $new_dir"
echo "Link:   $old_dir -> tls"
echo "Config: ${#config_files[@]} file(s) with the path \$HOME/ssl are changed (a copy is saved as .pre-tls)."

if [ "$dry_run" = true ]; then
  echo "Dry run: nothing was changed."
  exit 0
fi

# Do not move the directory during a renewal or a revocation.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$old_dir/.renew.lock"
  flock -n 9 || {
    print_error "A renewal or revocation is running. Try again later."
    exit 2
  }
else
  print_warning "flock is not installed, so overlapping runs are not prevented."
fi

if ! mv "$old_dir" "$new_dir"; then
  print_error "Could not move $old_dir to $new_dir."
  exit 1
fi

if ! ln -s tls "$old_dir"; then
  print_error "Could not create the link $old_dir. Moving the directory back."
  mv "$new_dir" "$old_dir" || print_error "Could not move it back. The files are in $new_dir."
  exit 1
fi

# Change the path in the configuration files, after a copy
changed=0
for file in "${config_files[@]}"; do
  file="$new_dir/openssl.cnf/$(basename "$file")"
  if sed -i.pre-tls 's#HOME/ssl#HOME/tls#g' "$file"; then
    changed=$((changed + 1))
  else
    print_warning "Could not change $file. The link $old_dir keeps the old path working."
  fi
done

echo
print_cyan "Moved $old_dir to $new_dir. $changed configuration file(s) changed."
echo "The old path $old_dir is now a link to $new_dir. Remove it when nothing uses it."
