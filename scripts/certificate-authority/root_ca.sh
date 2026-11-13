#!/bin/bash

# Script Name: root_ca.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 3.0.0

# Description:
# This script creates the Root Certificate Authority (CA), signed by the
# trusted identity. It generates an ECDSA key that is encrypted with a
# passphrase, creates the Certificate Signing Request (CSR), issues the
# certificate, creates the chain bundle, and verifies the result. The files are
# put in place after all checks passed. An existing key and certificate are
# copied to the archive first.

# Usage: ./root_ca.sh [--no-passphrase] [--name-constraints <list>] [-h|--help]
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
#  -h, --help       Show this help.
#
# Without --no-passphrase the script asks for a new passphrase, or reads it
# from the environment variable TLS_ROOT_CA_PASSPHRASE. When the key of the
# trusted identity is encrypted, the script asks for that passphrase too, or
# reads it from TLS_TRUSTED_ID_PASSPHRASE.

# Notes:
# - The certificates are for a homelab and for testing.
# - With --name-constraints, clients refuse a certificate for a name outside
#   the list. Name the DNS names and the IP networks: a type that is not in
#   the list is not limited. Add DNS:localhost and IP:127.0.0.0/8 when you use
#   the localhost certificate. To change the list, create the authority again.
# - Keep the passphrase. Without it the key cannot sign a new intermediate CA.
# - Overwriting the root CA requires a new intermediate CA and new
#   certificates.
# - The serial number is random (openssl ca -rand_serial). The script does not
#   change the serial or crlnumber file.
# - The certificate is recorded in the database of the trusted identity
#   ($HOME/tls/db/trusted_id/), not in the database of the certificates.
# - The old files are copied to $HOME/tls/archive/_ca/root_ca/ first.

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
name_constraints_list=""
key_passphrase=""
signer_passphrase=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --no-passphrase)
    use_passphrase=false
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
certs_dir="$base_dir/certs"
csr_dir="$base_dir/csr"
config_file="$base_dir/openssl.cnf/root_ca.cnf"
certs_root_dir="$certs_dir/root"
key_file="$base_dir/private/root/root_ca.pem"
cert_file="$certs_root_dir/root_ca.pem"
signer_key="$base_dir/private/root/trusted_id.pem"
signer_cert="$certs_root_dir/trusted_id.pem"
parent_chain="$certs_root_dir/trusted_id.pem"

enter_home 2

# The database of the authority that signs, as named in the configuration file
database=$(config_database "$config_file") || {
  print_error "Cannot read the database path from $config_file. Run tls_directory_setup.sh first."
  exit 2
}

# Check that everything needed is present, before anything changes
missing=false
for file in "$config_file" "$signer_key" "$signer_cert" "$parent_chain" "$database"; do
  if [[ ! -f "$file" ]]; then
    print_error "Required file not found: $file"
    missing=true
  fi
done
for dir in "$(dirname "$cert_file")" "$(dirname "$key_file")" "$csr_dir"; do
  if [[ ! -d "$dir" ]]; then
    print_error "Directory not found: $dir"
    missing=true
  fi
done
[[ "$missing" == "false" ]] || exit 2

# If unique_subject is enabled and the authority exists, display an error and exit
if [[ -f "$cert_file" ]]; then
  if unique_subject_enabled "$database.attr"; then
    print_error "unique_subject is enabled and Root Certificate Authority already exists."
    exit 2
  fi

  print_section_header "WARNING: Overwriting Root Certificate Authority"
  print_warning "Root Certificate Authority already exists and will be OVERWRITTEN!"
  print_warning "This action will require REGENERATING ALL SUB-CA CERTIFICATES, AND ALL ISSUED CERTIFICATES!"
  print_warning "If you continue, all issued certificates will become INVALID!"
  if ! confirm; then
    echo "[INFO] Operation aborted by user." >&2
    exit 1
  fi
fi

# Ask for the passphrases: the key that signs, and the new key
signer_options=()
if key_is_encrypted "$signer_key"; then
  get_passphrase signer_passphrase TLS_TRUSTED_ID_PASSPHRASE "trusted identity key" || exit 2
  signer_options=(-passin env:TLS_SIGNER_PASSPHRASE)
fi
key_options=()
pass_options=()
if [[ "$use_passphrase" == "true" ]]; then
  get_passphrase key_passphrase TLS_ROOT_CA_PASSPHRASE "new root CA key" new || exit 2
  key_options=(-aes-256-cbc -pass env:TLS_KEY_PASSPHRASE)
  pass_options=(-passin env:TLS_KEY_PASSPHRASE)
else
  print_warning "The private key of the root CA is not encrypted."
fi

# Work in a temporary folder that only the owner can read
work_dir=$(umask 077 && mktemp -d "$base_dir/.root_ca.XXXXXX")
trap cleanup EXIT
trap 'exit 1' INT TERM
new_key="$work_dir/key.pem"
new_csr="$work_dir/csr.pem"
new_cert="$work_dir/cert.pem"
new_chain="$work_dir/chain_bundle.pem"

# Generate ECDSA key
print_section_header "Generate ECDSA key"
(umask 077 && TLS_KEY_PASSPHRASE="$key_passphrase" openssl genpkey -algorithm EC \
  -pkeyopt ec_paramgen_curve:P-384 -pkeyopt ec_param_enc:named_curve \
  ${key_options[@]+"${key_options[@]}"} -out "$new_key")

# Generate Certificate Signing Request (CSR)
print_section_header "Generate Certificate Signing Request"
TLS_KEY_PASSPHRASE="$key_passphrase" openssl req -new -sha384 -config "$config_file" \
  -key "$new_key" ${pass_options[@]+"${pass_options[@]}"} -out "$new_csr"

# Generate Root Certificate Authority
print_section_header "Generate Root Certificate Authority"
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

TLS_SIGNER_PASSPHRASE="$signer_passphrase" openssl ca -config "$sign_config" -extensions v3_ca -rand_serial -notext -batch \
  ${signer_options[@]+"${signer_options[@]}"} -in "$new_csr" -days 7305 -out "$new_cert"

# Create Root Certificate Authority Chain Bundle
print_section_header "Create Root Certificate Authority Chain Bundle"
cat "$new_cert" "$parent_chain" >"$new_chain"

# Verify the certificate against the chain above it and the private key
print_section_header "Verify Certificate"
openssl verify -CAfile "$parent_chain" "$new_cert"
if [[ "$(openssl x509 -in "$new_cert" -noout -pubkey)" != \
"$(TLS_KEY_PASSPHRASE="$key_passphrase" openssl pkey -in "$new_key" ${pass_options[@]+"${pass_options[@]}"} -pubout)" ]]; then
  print_error "The certificate does not match the private key."
  exit 1
fi
echo "The certificate matches the private key."

# Put the files in place, after a copy of the existing files
print_section_header "Install the files"
archive_files "_ca/root_ca" "$key_file" "$cert_file" "${cert_file%.pem}.crt" \
  "${cert_file%.pem}_chain_bundle.pem" "${cert_file%.pem}_chain_bundle.crt" "$csr_dir/root_ca.pem"
mv -f "$new_key" "$key_file"
chmod 600 "$key_file"
cp -f "$new_csr" "$csr_dir/root_ca.pem"
cp -f "$new_cert" "$cert_file"
cp -f "$new_cert" "${cert_file%.pem}.crt"
cp -f "$new_chain" "${cert_file%.pem}_chain_bundle.pem"
cp -f "$new_chain" "${cert_file%.pem}_chain_bundle.crt"
echo
print_cyan "--> root_ca.pem and root_ca.crt"
print_cyan "--> root_ca_chain_bundle.pem and root_ca_chain_bundle.crt"

# Script completion message
echo
print_cyan "Root Certificate Authority process successfully completed."

exit 0
