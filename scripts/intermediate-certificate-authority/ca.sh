#!/bin/bash

# Script Name: ca.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 3.0.0

# Description:
# This script creates the Intermediate Certificate Authority (CA), signed by
# the root CA. It generates an ECDSA key, creates the Certificate Signing
# Request (CSR), issues the certificate, creates the chain bundle, and verifies
# the result. The files are put in place after all checks passed. An existing
# key and certificate are copied to the archive first.

# Usage: ./ca.sh [--passphrase] [-h|--help]
#
# Options:
#  --passphrase     Encrypt the private key with a passphrase. The certificate
#                   scripts and the renewal then ask for it at every run, so
#                   an unattended renewal is not possible.
#  -h, --help       Show this help.
#
# The key of the intermediate CA is not encrypted by default, because the
# certificate scripts and the renewal use it at every run. When the key of the
# root CA is encrypted, the script asks for that passphrase, or reads it from
# the environment variable TLS_ROOT_CA_PASSPHRASE. With --passphrase the new
# passphrase is asked for, or read from TLS_CA_PASSPHRASE.

# Notes:
# - The certificates are for a homelab and for testing.
# - Overwriting the intermediate CA requires new certificates.
# - Protect $HOME/tls/private: the key of the intermediate CA is not encrypted.
# - The serial number is random (openssl ca -rand_serial). The script does not
#   change db/serial or db/crlnumber.
# - The old files are copied to $HOME/tls/archive/_ca/ca/ first.

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

use_passphrase=false
work_dir=""
key_passphrase=""
signer_passphrase=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --passphrase)
    use_passphrase=true
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

require_openssl 2

# Define directory paths
print_section_header "Define directory paths"
set_base_dir
certs_dir="$base_dir/certs"
csr_dir="$base_dir/csr"
db_dir="$base_dir/db"
config_file="$base_dir/openssl.cnf/ca.cnf"
certs_root_dir="$certs_dir/root"
key_file="$base_dir/private/intermediate/ca.pem"
cert_file="$certs_dir/intermediate/ca.pem"
signer_key="$base_dir/private/root/root_ca.pem"
signer_cert="$certs_root_dir/root_ca.pem"
parent_chain="$certs_root_dir/root_ca_chain_bundle.pem"

enter_home 2

# Check that everything needed is present, before anything changes
missing=false
for file in "$config_file" "$signer_key" "$signer_cert" "$parent_chain" "$db_dir/index.txt"; do
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
  if unique_subject_enabled "$db_dir/index.txt.attr"; then
    print_error "unique_subject is enabled and Intermediate Certificate Authority already exists."
    exit 2
  fi

  print_section_header "WARNING: Overwriting Intermediate Certificate Authority"
  print_warning "Intermediate Certificate Authority already exists and will be OVERWRITTEN!"
  print_warning "This action will require REGENERATING ALL ISSUED CERTIFICATES!"
  print_warning "If you continue, all issued certificates will become INVALID!"
  if ! confirm; then
    echo "[INFO] Operation aborted by user." >&2
    exit 1
  fi
fi

# Ask for the passphrases: the key that signs, and the new key
signer_options=()
if key_is_encrypted "$signer_key"; then
  get_passphrase signer_passphrase TLS_ROOT_CA_PASSPHRASE "root CA key" || exit 2
  signer_options=(-passin env:TLS_SIGNER_PASSPHRASE)
fi
key_options=()
pass_options=()
if [[ "$use_passphrase" == "true" ]]; then
  get_passphrase key_passphrase TLS_CA_PASSPHRASE "new intermediate CA key" new || exit 2
  key_options=(-aes-256-cbc -pass env:TLS_KEY_PASSPHRASE)
  pass_options=(-passin env:TLS_KEY_PASSPHRASE)
fi

# Work in a temporary folder that only the owner can read
work_dir=$(umask 077 && mktemp -d "$base_dir/.ca.XXXXXX")
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

# Generate Intermediate Certificate Authority
print_section_header "Generate Intermediate Certificate Authority"
TLS_SIGNER_PASSPHRASE="$signer_passphrase" openssl ca -config "$config_file" -extensions v3_intermediate_ca -rand_serial -notext -batch \
  ${signer_options[@]+"${signer_options[@]}"} -in "$new_csr" -days 1826 -out "$new_cert"

# Create Intermediate Certificate Authority Chain Bundle
print_section_header "Create Intermediate Certificate Authority Chain Bundle"
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
archive_files "_ca/ca" "$key_file" "$cert_file" "${cert_file%.pem}.crt" \
  "${cert_file%.pem}_chain_bundle.pem" "${cert_file%.pem}_chain_bundle.crt" "$csr_dir/ca.pem"
mv -f "$new_key" "$key_file"
chmod 600 "$key_file"
cp -f "$new_csr" "$csr_dir/ca.pem"
cp -f "$new_cert" "$cert_file"
cp -f "$new_cert" "${cert_file%.pem}.crt"
cp -f "$new_chain" "${cert_file%.pem}_chain_bundle.pem"
cp -f "$new_chain" "${cert_file%.pem}_chain_bundle.crt"
echo
print_cyan "--> ca.pem and ca.crt"
print_cyan "--> ca_chain_bundle.pem and ca_chain_bundle.crt"

# Script completion message
echo
print_cyan "Intermediate Certificate Authority process successfully completed."

exit 0
