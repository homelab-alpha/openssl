#!/bin/bash

# Script Name: ca.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-16T12:08:42+01:00
# Version: 2.0.0

# Description:
# This script facilitates the setup and management of an Intermediate Certificate
# Authority (CA). It automates the process of generating ECDSA keys, creating
# a Certificate Signing Request (CSR), issuing the intermediate CA certificate,
# creating the CA chain bundle, and verifying the integrity of the certificates.
# It also provides conversion for HAProxy compatibility and supports certificate format conversion.

# Usage: ./ca.sh

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
if grep -q "^unique_subject\s*=\s*yes" "$intermediate_dir/db/index.txt.attr" 2>/dev/null; then
  unique_subject="yes"
fi

cn_exists=false
if grep -q "CN=HA" "$intermediate_dir/db/index.txt" 2>/dev/null; then
  cn_exists=true
fi

if [[ "$unique_subject" == "yes" && "$cn_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and CSR with Common Name HA already exists in index.txt" >&2
  exit 1
fi

# Generate ECDSA key for Intermediate CA
print_section_header "Generate ECDSA key for Intermediate CA"
openssl ecparam -name secp384r1 -genkey -out "$intermediate_dir/private/ca.pem"
check_success "Failed to generate ECDSA key for Intermediate CA"

# Generate Certificate Signing Request (CSR) for Intermediate CA
print_section_header "Generate Certificate Signing Request (CSR) for Intermediate CA"
openssl req -new -sha384 -config "$intermediate_dir/ca.cnf" -key "$intermediate_dir/private/ca.pem" -out "$intermediate_dir/csr/ca.pem"
check_success "Failed to generate CSR for Intermediate CA"

# Generate Intermediate Certificate Authority
print_section_header "Generate Intermediate Certificate Authority"
openssl ca -config "$intermediate_dir/ca.cnf" -extensions v3_intermediate_ca -notext -batch -in "$intermediate_dir/csr/ca.pem" -days 1826 -out "$intermediate_dir/certs/ca.pem"
check_success "Failed to generate Intermediate CA certificate"

# Create Intermediate Certificate Authority Chain Bundle
print_section_header "Create Intermediate Certificate Authority Chain Bundle"
cat "$intermediate_dir/certs/ca.pem" "$root_dir/certs/root_ca_chain_bundle.pem" >"$intermediate_dir/certs/ca_chain_bundle.pem"
check_success "Failed to create Intermediate CA chain bundle"

# Function to verify certificates
verify_certificate() {
  openssl verify -CAfile "$1" "$2"
  check_success "Verification failed for $2"
}

# Perform certificate verifications
print_section_header "Verify Certificates"
verify_certificate "$intermediate_dir/certs/ca_chain_bundle.pem" "$intermediate_dir/certs/ca.pem"
verify_certificate "$root_dir/certs/root_ca_chain_bundle.pem" "$intermediate_dir/certs/ca.pem"
verify_certificate "$root_dir/certs/root_ca_chain_bundle.pem" "$intermediate_dir/certs/ca_chain_bundle.pem"

exit 0
