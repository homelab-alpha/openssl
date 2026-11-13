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
#
# Every authority has its own database, so a CRL and the unique_subject check
# only cover the certificates that the authority issued itself:
#   $HOME/tls/db/trusted_id/  the root CA, issued by the trusted identity
#   $HOME/tls/db/root_ca/     the intermediate CA, issued by the root CA
#   $HOME/tls/db/             the certificates, issued by the intermediate CA
# Older versions used $HOME/tls/db/ for all three. When the configuration
# files name the new databases (after --update-config), the script moves the
# entries of the root CA and the intermediate CA to their own database. A copy
# of index.txt is saved first in $HOME/tls/archive/_database/.

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

# Function to move the database entry of an authority certificate from the
# shared database ($db_dir/index.txt) to the database that its configuration
# file names. The certificate copy in newcerts moves with it.
# Usage: move_authority_entry <configuration file> <certificate>
move_authority_entry() {
  local config="$1" cert="$2" shared="$db_dir/index.txt" target serial line backup_dir newcerts_dir
  [[ -f "$config" && -f "$cert" && -f "$shared" ]] || return 0
  target=$(config_database "$config") || return 0
  [[ "$target" != "$shared" && -f "$target" ]] || return 0
  serial=$(openssl x509 -in "$cert" -noout -serial 2>/dev/null) || return 0
  serial="${serial#serial=}"
  line=$(awk -F'\t' -v s="$serial" 'toupper($4) == toupper(s)' "$shared")
  [[ -n "$line" ]] || return 0
  if awk -F'\t' -v s="$serial" 'toupper($4) == toupper(s) { found = 1 } END { exit !found }' "$target"; then
    return 0
  fi

  if [[ "$moved" == "false" ]]; then
    # Do not change the database during a renewal or a revocation
    if command -v flock >/dev/null 2>&1; then
      exec 9>"$base_dir/.renew.lock"
      flock -n 9 || {
        print_error "A renewal or revocation is running. Try again later."
        return 1
      }
    fi
    backup_dir="$base_dir/archive/_database"
    (umask 077 && mkdir -p "$backup_dir" &&
      cp -p "$shared" "$backup_dir/index.txt.$(date -u +%Y%m%dT%H%M%SZ)") || {
      print_error "Cannot save a copy of $shared. Nothing was moved."
      return 1
    }
  fi
  printf '%s\n' "$line" >>"$target" || return 1
  awk -F'\t' -v s="$serial" 'toupper($4) != toupper(s)' "$shared" >"$shared.tmp" || return 1
  mv -f "$shared.tmp" "$shared" || return 1
  newcerts_dir="$base_dir/newcerts/$(basename "$(dirname "$target")")"
  if [[ -f "$base_dir/newcerts/$serial.pem" && -d "$newcerts_dir" ]]; then
    mv -f "$base_dir/newcerts/$serial.pem" "$newcerts_dir/$serial.pem" || return 1
  fi
  moved=true
  echo "Moved:   entry $serial of $(basename "$cert") to $target"
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
  "$base_dir/newcerts"/{trusted_id,root_ca} \
  "$private_dir"/{root,intermediate,certificates} \
  "$db_dir"/{trusted_id,root_ca} \
  "$base_dir/log" \
  "$openssl_conf_dir" \
  "$tsa_dir"/{certs,db}

# Create the db files. Existing files are kept: a new serial or CRL number
# would break the order of the numbers that are in use.
print_section_header "Creating db files"
for dir in "$db_dir" "$db_dir/trusted_id" "$db_dir/root_ca" "$tsa_dir/db"; do
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

# Move the entries of the authorities out of the shared database of an older
# version. Nothing happens on a new setup, or while the configuration files
# still name the shared database.
print_section_header "Checking the databases of the authorities"
moved=false
move_authority_entry "$openssl_conf_dir/root_ca.cnf" "$certs_dir/root/root_ca.pem" || exit 1
move_authority_entry "$openssl_conf_dir/ca.cnf" "$certs_dir/intermediate/ca.pem" || exit 1
[[ "$moved" == "true" ]] || echo "Nothing to move."

# Script completion message
echo
print_cyan "TLS directory setup completed successfully."
