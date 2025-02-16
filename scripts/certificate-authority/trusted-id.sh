#!/bin/bash

# Script Name: trusted-id.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-16T12:08:42+01:00
# Version: 2.0.0

# Description:
# This script generates and manages a trusted root certificate. It sets up
# directory paths, renews database serial numbers, generates an ECDSA key,
# creates a self-signed certificate, verifies the certificate, checks the
# private key, and converts the certificate format.

# Usage: ./trusted-id.sh

# Stop script on error
set -e

# Function to print text in cyan color
print_cyan() {
  echo -e "\e[36m$1\e[0m"
}

# Function to generate a random hex value
generate_random_hex() {
  openssl rand -hex 16 || return 1
}

# Function to print section headers.
print_section_header() {
  echo ""
  print_cyan "=== $1 ==="
}

# Function to check command success
check_success() {
  if [ $? -ne 0 ]; then
    echo "[ERROR] $1" >&2
    exit 1
  fi
}

# Define directory paths
print_section_header "Define directory paths"
ssl_dir="$HOME/ssl"
root_dir="$ssl_dir/root"
intermediate_dir="$ssl_dir/intermediate"
tsa_dir="$ssl_dir/tsa"

# Renew db numbers (serial and CRL)
print_section_header "Renew db numbers (serial and CRL)"
for type in "serial" "crlnumber"; do
  for dir in "$root_dir/db" "$intermediate_dir/db" "$tsa_dir/db"; do
    generate_random_hex >"$dir/$type" || check_success "Failed to generate $type for $dir"
  done
done

# Check if unique_subject is enabled and if CN exists
unique_subject="no"
if grep -q "^unique_subject\s*=\s*yes" "$root_dir/db/index.txt.attr" 2>/dev/null; then
  unique_subject="yes"
fi

cn_exists=false
if grep -q "CN=HATS Root X1" "$root_dir/db/index.txt" 2>/dev/null; then
  cn_exists=true
fi

if [[ "$unique_subject" == "yes" && "$cn_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and CSR with Common Name HATS Root X1 already exists in index.txt" >&2
  exit 1
fi

# Generate ECDSA key for Trusted ID
print_section_header "Generate ECDSA key for Trusted ID"
openssl ecparam -name secp384r1 -genkey -out "$root_dir/private/trusted-id.pem"
check_success "Failed to generate ECDSA key"

# Generate Certificate Signing Request (CSR) for Trusted ID
print_section_header "Generate Certificate Signing Request (CSR) for Trusted ID"
openssl req -new -x509 -sha384 -config "$root_dir/trusted-id.cnf" -extensions v3_ca -key "$root_dir/private/trusted-id.pem" -days 10956 -out "$root_dir/certs/trusted-id.pem"
check_success "Failed to generate certificate"

# Verify Certificate against itself.
print_section_header "Verify Certificate against itself"
openssl verify -CAfile "$root_dir/certs/trusted-id.pem" "$root_dir/certs/trusted-id.pem"
check_success "Verification failed for certificate"

# Check Private Key.
print_section_header "Check Private Key"
openssl ecparam -in "$root_dir/private/trusted-id.pem" -text -noout
check_success "Failed to check private key"

# Check Certificate.
print_section_header "Check Certificate"
openssl x509 -in "$root_dir/certs/trusted-id.pem" -text -noout
check_success "Failed to check certificate"

# Convert Certificate from .pem to .crt.
print_section_header "Convert from trusted-id.pem to trusted-id.crt"
cp "$root_dir/certs/trusted-id.pem" "$root_dir/certs/trusted-id.crt"
check_success "Failed to convert certificate"

print_cyan "--> trusted-id.crt"

exit 0
