#!/bin/bash

# Script Name: tls_directory_setup.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 3.0.0

# Description:
# This script sets up the directory structure for TLS certificate management
# under $HOME/tls. It creates the database files and copies the OpenSSL
# configuration files from the repository.
#
# The script is safe to run again: it creates what is missing and does not
# change a file that exists. The database files (index.txt, index.txt.attr,
# serial, and crlnumber) and the configuration files in $HOME/tls/openssl.cnf
# are kept as they are.

# Usage: ./tls_directory_setup.sh [--update-config] [-h|--help]
#
# Options:
#  --update-config  Replace the configuration files in $HOME/tls/openssl.cnf
#                   that differ from the repository. Each replaced file is
#                   saved first with the extension .bak-<date>.
#  -h, --help       Show this help.

# Notes:
# - Ensure OpenSSL is installed before running the script.
# - The configuration files are read from the folder openssl.cnf of the
#   repository that holds this script.
# - The folders for private keys get mode 700 when the script creates them.
# - The certificates are for a homelab and for testing.

# Stop script on error
set -Eeuo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh"

update_config=false
while [[ $# -gt 0 ]]; do
  case "$1" in
  --update-config)
    update_config=true
    shift
    ;;
  -h | --help)
    show_usage '^# Notes:'
    exit 0
    ;;
  *)
    print_error "Unknown option: $1"
    exit 2
    ;;
  esac
done

require_openssl

# Set base directory
base_dir="$HOME/tls"
# Do not create a second, empty directory while the old one exists.
if [[ ! -e "$base_dir" && -d "$HOME/ssl" ]]; then
  print_error "The old directory $HOME/ssl exists. Run tls_directory_migrate.sh to move it to $HOME/tls."
  exit 1
fi
certs_dir="$base_dir/certs"
private_dir="$base_dir/private"
db_dir="$base_dir/db"
openssl_conf_dir="$base_dir/openssl.cnf"
tsa_dir="$base_dir/tsa"
source_conf_dir="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/openssl.cnf"

# Function to create a file with the given content when it does not exist
create_if_missing() {
  local file="$1" content="$2"
  if [[ -e "$file" ]]; then
    echo "Kept:    $file"
  else
    printf '%s\n' "$content" >"$file"
    echo "Created: $file"
  fi
}

# Create directory structure. Private key folders are for the owner only.
print_section_header "Creating directory structure"
for dir in "$private_dir" "$tsa_dir/private"; do
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    chmod 700 "$dir"
  fi
done
mkdir -p "$certs_dir"/{root,intermediate,certificates} \
  "$base_dir/crl" \
  "$base_dir/crl-backup" \
  "$base_dir/csr" \
  "$base_dir/extfiles" \
  "$base_dir/newcerts" \
  "$private_dir"/{root,intermediate,certificates} \
  "$db_dir" \
  "$base_dir/log" \
  "$openssl_conf_dir" \
  "$tsa_dir"/{certs,db}

# Create the db files. Existing files are kept: a new serial or CRL number
# would break the order of the numbers that are in use.
print_section_header "Creating db files"
for dir in "$db_dir" "$tsa_dir/db"; do
  if [[ -e "$dir/index.txt" ]]; then
    echo "Kept:    $dir/index.txt"
  else
    : >"$dir/index.txt"
    echo "Created: $dir/index.txt"
  fi
  create_if_missing "$dir/index.txt.attr" "unique_subject = yes"
  create_if_missing "$dir/serial" "$(openssl rand -hex 16)"
  create_if_missing "$dir/crlnumber" "1000"
done

# Copy OpenSSL configuration files to the target directory
print_section_header "Copying OpenSSL configuration files"
if [[ -d "$source_conf_dir" ]]; then
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  for file in "$source_conf_dir"/*.cnf; do
    [[ -f "$file" ]] || continue
    target="$openssl_conf_dir/$(basename "$file")"
    if [[ ! -e "$target" ]]; then
      cp "$file" "$target"
      echo "Created: $target"
    elif cmp -s "$file" "$target"; then
      echo "Kept:    $target"
    elif [[ "$update_config" == "true" ]]; then
      cp -p "$target" "$target.bak-$stamp"
      cp "$file" "$target"
      echo "Updated: $target (the old file is $target.bak-$stamp)"
    else
      echo "Kept:    $target (differs from the repository; use --update-config to replace it)"
    fi
  done
else
  print_warning "OpenSSL configuration directory not found at $source_conf_dir."
  echo "Skipping OpenSSL configuration files copy."
fi

# Script completion message
echo
print_cyan "TLS directory setup completed successfully."
