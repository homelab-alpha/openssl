#!/bin/bash

# Script Name: ca.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-19T11:16:16+01:00
# Version: 2.6.2

# Description:
# This script automates the process of setting up and managing an
# Intermediate Certificate Authority (CA). It generates ECDSA keys,
# creates a Certificate Signing Request (CSR), issues the Intermediate
# CA certificate, creates the CA chain bundle, and verifies the
# integrity of the certificates. It also supports certificate format
# conversion and conversion for HAProxy compatibility.

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
  echo
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
base_dir="$HOME/ssl"
certs_dir="$base_dir/certs"
csr_dir="$base_dir/csr"
private_dir="$base_dir/private"
db_dir="$base_dir/db"
openssl_conf_dir="$base_dir/openssl.cnf"

# Set directories for various components
certs_root_dir="$certs_dir/root"
certs_intermediate_dir="$certs_dir/intermediate"
private_intermediate_dir="$private_dir/intermediate"

# Renew db numbers (serial and CRL)
print_section_header "Renew db numbers (serial and CRL)"
for type in "serial" "crlnumber"; do
  for dir in $db_dir; do
    generate_random_hex >"$dir/$type" || check_success "Failed to generate $type for $dir"
  done
done

# Check if unique_subject is enabled and if trusted_id.pem exists
unique_subject="no"
if grep -q "^unique_subject\s*=\s*yes" "$db_dir/index.txt.attr" 2>/dev/null; then
  unique_subject="yes"
fi

ca_path="$certs_intermediate_dir/ca.pem"
trusted_id_exists=false
if [[ -f "$ca_path" ]]; then
  trusted_id_exists=true
fi

# If unique_subject is enabled and Intermediate Certificate Authority exists, display an error and exit
if [[ "$unique_subject" == "yes" && "$trusted_id_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and Intermediate Certificate Authority already exists." >&2
  exit 1
fi

# If unique_subject is "no", warn and ask for confirmation
if [[ "$unique_subject" == "no" && -f "$ca_path" ]]; then
  print_section_header "⚠️  WARNING: Overwriting Intermediate Certificate Authority"

  echo "[WARNING] Intermediate Certificate Authority already exists and will be OVERWRITTEN!" >&2
  echo "[WARNING] This action will require REGENERATING ALL ISSUED CERTIFICATES!" >&2
  echo "[WARNING] If you continue, all issued certificates will become INVALID!" >&2

  read -r -p "Do you want to continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "[INFO] Operation aborted by user." >&2
    exit 1
  fi
fi

# Generate ECDSA key for Intermediate CA
print_section_header "Generate ECDSA key for Intermediate CA"
openssl ecparam -name secp384r1 -genkey -out "$private_intermediate_dir/ca.pem"
check_success "Failed to generate ECDSA key for Intermediate CA"

# Generate Certificate Signing Request (CSR) for Intermediate CA
print_section_header "Generate Certificate Signing Request (CSR) for Intermediate CA"
openssl req -new -sha384 -config "$openssl_conf_dir/ca.cnf" -key "$private_intermediate_dir/ca.pem" -out "$csr_dir/ca.pem"
check_success "Failed to generate CSR for Intermediate CA"

# Generate Intermediate Certificate Authority
print_section_header "Generate Intermediate Certificate Authority"
openssl ca -config "$openssl_conf_dir/ca.cnf" -extensions v3_intermediate_ca -notext -batch -in "$csr_dir/ca.pem" -days 1826 -out "$certs_intermediate_dir/ca.pem"
check_success "Failed to generate Intermediate CA certificate"

# Create Intermediate Certificate Authority Chain Bundle
print_section_header "Create Intermediate Certificate Authority Chain Bundle"
cat "$certs_intermediate_dir/ca.pem" "$certs_root_dir/root_ca_chain_bundle.pem" >"$certs_intermediate_dir/ca_chain_bundle.pem"
check_success "Failed to create Intermediate CA chain bundle"

# Function to verify certificates
verify_certificate() {
  openssl verify -CAfile "$1" "$2"
  check_success "Verification failed for $2"
}

# Perform certificate verifications
print_section_header "Verify Certificates"
verify_certificate "$certs_intermediate_dir/ca_chain_bundle.pem" "$certs_intermediate_dir/ca.pem"
verify_certificate "$certs_root_dir/root_ca_chain_bundle.pem" "$certs_intermediate_dir/ca.pem"
verify_certificate "$certs_root_dir/root_ca_chain_bundle.pem" "$certs_intermediate_dir/ca_chain_bundle.pem"

# Convert Certificate from .pem to .crt.
print_section_header "Convert Intermediate Certificate Authority Formats"
cp "$certs_intermediate_dir/ca.pem" "$certs_intermediate_dir/ca.crt"
cp "$certs_intermediate_dir/ca_chain_bundle.pem" "$certs_intermediate_dir/ca_chain_bundle.crt"
check_success "Failed to convert certificate"
echo
print_cyan "--> ca.crt"
print_cyan "--> ca_chain_bundle.crt"

# Script completion message
echo
print_cyan "Intermediate Certificate Authority process successfully completed."

exit 0
