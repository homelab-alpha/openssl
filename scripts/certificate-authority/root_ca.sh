#!/bin/bash

# Script Name: root_ca.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-16T15:01:25+01:00
# Version: 2.1.0

# Description:
# This script sets up and manages a Root Certificate Authority (CA). It defines
# necessary directory paths, renews database serial numbers, generates ECDSA keys,
# creates Certificate Signing Requests (CSRs), and issues the root certificate.
# Additionally, it verifies the root certificate and creates a CA chain bundle,
# ensuring the integrity and correctness of the generated keys, CSRs, and certificates.

# Usage: ./root_ca.sh

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
if grep -q "CN=HA Root X1" "$root_dir/db/index.txt" 2>/dev/null; then
  cn_exists=true
fi

# If unique_subject is enabled and CN exists, display an error and exit
if [[ "$unique_subject" == "yes" && "$cn_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and CSR with Common Name HA Root X1 already exists in index.txt" >&2
  exit 1
fi

# If unique_subject is "no", warn and ask for confirmation
if [[ "$unique_subject" == "no" ]]; then
  print_section_header "⚠️  WARNING: Overwriting Root CA"

  echo "[WARNING] Root CA already exists and will be OVERWRITTEN!" >&2
  echo "[WARNING] This action will require REGENERATING ALL SUB-CA CERTIFICATES AND ALL ISSUED CERTIFICATES!" >&2
  echo "[WARNING] If you continue, all issued certificates will become INVALID!" >&2

  read -p "Do you want to continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "[INFO] Operation aborted by user." >&2
    exit 1
  fi
fi

# Generate ECDSA key for Root CA
print_section_header "Generate ECDSA key for Root CA"
openssl ecparam -name secp384r1 -genkey -out "$root_dir/private/root_ca.pem"
check_success "Failed to generate ECDSA key for Root CA"

# Generate Certificate Signing Request (CSR) for Root CA
print_section_header "Generate Certificate Signing Request (CSR) for Root CA"
openssl req -new -sha384 -config "$root_dir/root_ca.cnf" -key "$root_dir/private/root_ca.pem" -out "$root_dir/csr/root_ca.pem"
check_success "Failed to generate CSR for Root CA"

# Generate Root Certificate Authority
print_section_header "Generate Root Certificate Authority"
openssl ca -config "$root_dir/root_ca.cnf" -extensions v3_ca -notext -batch -in "$root_dir/csr/root_ca.pem" -days 7305 -out "$root_dir/certs/root_ca.pem"
check_success "Failed to generate Root CA certificate"

# Create Root Certificate Authority Chain Bundle
print_section_header "Create Root Certificate Authority Chain Bundle"
cat "$root_dir/certs/root_ca.pem" "$root_dir/certs/trusted-id.pem" >"$root_dir/certs/root_ca_chain_bundle.pem"
check_success "Failed to create Root CA chain bundle"

# Function to verify certificates
verify_certificate() {
  openssl verify -CAfile "$1" "$2"
  check_success "Verification failed for $2"
}

# Perform certificate verifications
print_section_header "Verify Certificates"
verify_certificate "$root_dir/certs/root_ca_chain_bundle.pem" "$root_dir/certs/root_ca.pem"
verify_certificate "$root_dir/certs/trusted-id.pem" "$root_dir/certs/root_ca.pem"
verify_certificate "$root_dir/certs/trusted-id.pem" "$root_dir/certs/root_ca_chain_bundle.pem"

exit 0
