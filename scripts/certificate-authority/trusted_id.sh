#!/bin/bash

# Script Name: trusted_id.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 3.0.0

# Description:
# This script generates the trusted identity: the self-signed certificate at
# the top of the chain. It generates an ECDSA key that is encrypted with a
# passphrase, creates the self-signed certificate, verifies it, and checks
# the private key. The files are put in place after all checks passed. An
# existing key and certificate are copied to the archive first.

# Usage: ./trusted_id.sh [--no-passphrase] [--name-constraints <list>] [--replace [--yes]] [-h|--help]
#
# Options:
#  --no-passphrase  Do not encrypt the private key. Anyone who can read the
#                   file can then sign certificates.
#  --name-constraints <list>
#                   Limit the names that this authority, and every authority
#                   below it, can sign for. The list is separated by commas:
#                   DNS:<domain> (the domain and its subdomains) and
#                   IP:<IPv4 network>/<prefix>. For example
#                   "DNS:example.test, DNS:localhost, IP:192.168.0.0/16"
#                   A space after a comma is allowed, with or without the
#                   quotes. Can be repeated. Without this option there is no
#                   limit.
#  --replace       Create the trusted identity again when it exists. The old key
#                   and certificate are copied to the archive. Without this
#                   option an existing trusted identity is never changed.
#  --yes            Used with --replace. Do not ask for confirmation.
#  -h, --help       Show this help.
#
# Without --no-passphrase the script asks for a new passphrase, or reads it
# from the environment variable TLS_TRUSTED_ID_PASSPHRASE.

# Notes:
# - The certificates are for a homelab and for testing.
# - With --name-constraints, clients refuse a certificate for a name outside
#   the list. Not every client applies the limit of a certificate that is in
#   its trust store, so also set the option for the root CA. Name the DNS
#   names and the IP networks: a type that is not in the list is not limited.
# - Keep the passphrase. Without it the key cannot sign a new root CA.
# - Overwriting the trusted identity requires a new root CA, a new intermediate
#   CA, and new certificates.
# - The old files are copied to $HOME/tls/archive/_ca/trusted_id/ first.

# Stop script on error
set -Eeuo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

# Function to remove the temporary folder. It runs from the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    rm -rf "$work_dir"
  fi
}

use_passphrase=true
work_dir=""
replace=false
assume_yes=false
name_constraints_list=""
key_passphrase=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --no-passphrase)
    use_passphrase=false
    shift
    ;;
  --replace)
    replace=true
    shift
    ;;
  --yes)
    assume_yes=true
    shift
    ;;
  --name-constraints)
    [[ -n "${2:-}" ]] || {
      print_error "--name-constraints needs a list, for example \"DNS:example.test, IP:192.168.0.0/16\"."
      exit 2
    }
    name_constraints_list+="${name_constraints_list:+,}$2"
    shift 2
    # Without quotes, the shell splits "a, b" into separate arguments. Take the
    # next argument as well when the list so far ends with a comma, or when the
    # next argument starts with a comma.
    while [[ $# -gt 0 && "$1" != -* ]] && [[ "$name_constraints_list" == *, || "$1" == ,* ]]; do
      name_constraints_list+="$1"
      shift
    done
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

# Validate the permitted names and build the value of the extension
name_constraints=""
if [[ -n "$name_constraints_list" ]]; then
  name_constraints=$(build_name_constraints "$name_constraints_list") || {
    print_error "Invalid --name-constraints list: $name_constraints_list"
    echo "Use DNS:<domain> and IP:<IPv4 network>/<prefix>, separated by commas (for example \"DNS:example.test, IP:192.168.0.0/16\")." >&2
    exit 2
  }
fi

require_openssl 2

# Define directory paths
print_section_header "Define directory paths"
set_base_dir
certs_root_dir="$base_dir/certs/root"
private_root_dir="$base_dir/private/root"
config_file="$base_dir/openssl.cnf/trusted_id.cnf"
key_file="$private_root_dir/trusted_id.pem"
cert_file="$certs_root_dir/trusted_id.pem"

enter_home 2

# Check that everything needed is present, before anything changes
if [[ ! -f "$config_file" || ! -d "$certs_root_dir" || ! -d "$private_root_dir" ]]; then
  print_error "The directory structure in $base_dir is not complete. Run tls_directory_setup.sh first."
  exit 2
fi

# An existing trusted identity is only replaced with --replace
if [[ -f "$cert_file" ]]; then
  if [[ "$replace" == "false" ]]; then
    print_error "Trusted ID already exists. Use --replace to create it again."
    exit 2
  fi

  print_section_header "WARNING: Overwriting Trusted ID"
  print_warning "Trusted ID already exists and will be OVERWRITTEN!"
  print_warning "This action will require REGENERATING THE ROOT CA, ALL SUB-CA CERTIFICATES, AND ALL ISSUED CERTIFICATES!"
  print_warning "If you continue, all issued certificates will become INVALID!"
  if [[ "$assume_yes" == "false" ]] && ! confirm; then
    echo "[INFO] Operation aborted by user." >&2
    exit 1
  fi
fi

# Ask for the passphrase of the new key
key_options=()
pass_options=()
if [[ "$use_passphrase" == "true" ]]; then
  get_passphrase key_passphrase TLS_TRUSTED_ID_PASSPHRASE "new trusted identity key" new || exit 2
  key_options=(-aes-256-cbc -pass env:TLS_KEY_PASSPHRASE)
  pass_options=(-passin env:TLS_KEY_PASSPHRASE)
else
  print_warning "The private key of the trusted identity is not encrypted."
fi

# Work in a temporary folder that only the owner can read
work_dir=$(umask 077 && mktemp -d "$base_dir/.trusted_id.XXXXXX")
trap cleanup EXIT
trap 'exit 1' INT TERM
new_key="$work_dir/key.pem"
new_cert="$work_dir/cert.pem"

# Generate ECDSA key
print_section_header "Generate ECDSA key"
(umask 077 && TLS_KEY_PASSPHRASE="$key_passphrase" openssl genpkey -algorithm EC \
  -pkeyopt ec_paramgen_curve:P-384 -pkeyopt ec_param_enc:named_curve \
  ${key_options[@]+"${key_options[@]}"} -out "$new_key")

# Generate the self-signed certificate
print_section_header "Generate Trusted ID Certificate"
# With --name-constraints the extension is added to a copy of the configuration
# file. The file in $HOME/tls/openssl.cnf is not changed.
sign_config="$config_file"
if [[ -n "$name_constraints" ]]; then
  if grep -Eq '^[[:space:]]*nameConstraints[[:space:]]*=' "$config_file"; then
    print_error "$config_file already sets nameConstraints. Remove that line, or run without --name-constraints."
    exit 2
  fi
  sign_config="$work_dir/sign.cnf"
  config_with_extension "$config_file" "v3_ca" "nameConstraints = $name_constraints" "$sign_config" || {
    print_error "The section [ v3_ca ] was not found in $config_file."
    exit 2
  }
  echo "Name constraints: $name_constraints"
fi

TLS_KEY_PASSPHRASE="$key_passphrase" openssl req -new -x509 -sha384 -config "$sign_config" -extensions v3_ca \
  -key "$new_key" ${pass_options[@]+"${pass_options[@]}"} -days 10956 -out "$new_cert"

# Perform certificate verifications
print_section_header "Verify Certificate"
openssl verify -CAfile "$new_cert" "$new_cert"

# Check Private Key.
print_section_header "Check Private Key"
TLS_KEY_PASSPHRASE="$key_passphrase" openssl pkey -in "$new_key" ${pass_options[@]+"${pass_options[@]}"} -noout -check
if [[ "$(openssl x509 -in "$new_cert" -noout -pubkey)" != \
"$(TLS_KEY_PASSPHRASE="$key_passphrase" openssl pkey -in "$new_key" ${pass_options[@]+"${pass_options[@]}"} -pubout)" ]]; then
  print_error "The certificate does not match the private key."
  exit 1
fi
echo "The certificate matches the private key."

# Check Certificate.
print_section_header "Check Certificate"
openssl x509 -in "$new_cert" -text -noout

# Put the files in place, after a copy of the existing files. All files are
# copied next to their target first and then renamed, so a failure does not
# leave a mix of old and new files.
print_section_header "Install the files"
archive_files "_ca/trusted_id" "$key_file" "$cert_file" "$certs_root_dir/trusted_id.crt"
install_files \
  "$new_key" "$key_file" \
  "$new_cert" "$cert_file" \
  "$new_cert" "$certs_root_dir/trusted_id.crt" || {
  print_error "Cannot put the new files in place. The existing files were not changed."
  exit 1
}
echo
print_cyan "--> trusted_id.pem and trusted_id.crt"

# Script completion message
echo
print_cyan "Trusted ID Certificate Authority process successfully completed."

exit 0
