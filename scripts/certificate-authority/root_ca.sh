#!/bin/bash

# Script Name: root_ca.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-18T17:31:25+01:00
# Version: 2.5.0

# Description:
# This script sets up and manages a Root Certificate Authority (CA). It
# defines necessary directory paths, renews database serial numbers,
# generates ECDSA keys, creates Certificate Signing Requests (CSRs), and
# issues the root certificate. Additionally, it verifies the root certificate
# and creates a CA chain bundle, ensuring the integrity of the generated keys,
# CSRs, and certificates.

# Usage: ./root_ca.sh

# Notes:
# - The script overwrites an existing Root CA if `unique_subject` is set to "no".
# - Make sure the openssl configuration files exist and are correctly set up.
# - The script requires proper permissions to write to the defined directories.
# - Ensure `openssl` is installed and accessible in your environment.

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
base_dir="$HOME/ssl"
certs_dir="$base_dir/certs"
csr_dir="$base_dir/csr"
private_dir="$base_dir/private"
db_dir="$base_dir/db"
openssl_conf_dir="$base_dir/openssl.cnf"

# Set directories for various components
certs_root_dir="$certs_dir/root"
private_root_dir="$private_dir/root"

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

root_ca_path="$certs_root_dir/root_ca.pem"
trusted_id_exists=false
if [[ -f "$root_ca_path" ]]; then
  trusted_id_exists=true
fi

# If unique_subject is enabled and Certificate Authority exists, display an error and exit
if [[ "$unique_subject" == "yes" && "$trusted_id_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and Certificate Authority already exists." >&2
  exit 1
fi

# If unique_subject is "no", warn and ask for confirmation
if [[ "$unique_subject" == "no" && -f "$root_ca_path" ]]; then
  print_section_header "⚠️  WARNING: Overwriting Certificate Authority"

  echo "[WARNING] Certificate Authority already exists and will be OVERWRITTEN!" >&2
  echo "[WARNING] This action will require REGENERATING ALL SUB-CA CERTIFICATES, AND ALL ISSUED CERTIFICATES!" >&2
  echo "[WARNING] If you continue, all issued certificates will become INVALID!" >&2

  read -p -r "Do you want to continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "[INFO] Operation aborted by user." >&2
    exit 1
  fi
fi

# Generate ECDSA key for Root CA
print_section_header "Generate ECDSA key for Root CA"
openssl ecparam -name secp384r1 -genkey -out "$private_root_dir/root_ca.pem"
check_success "Failed to generate ECDSA key for Root CA"

# Generate Certificate Signing Request (CSR) for Root CA
print_section_header "Generate Certificate Signing Request (CSR) for Root CA"
openssl req -new -sha384 -config "$openssl_conf_dir/root_ca.cnf" -key "$private_root_dir/root_ca.pem" -out "$csr_dir/root_ca.pem"
check_success "Failed to generate CSR for Root CA"

# Generate Root Certificate Authority
print_section_header "Generate Root Certificate Authority"
openssl ca -config "$openssl_conf_dir/root_ca.cnf" -extensions v3_ca -notext -batch -in "$csr_dir/root_ca.pem" -days 7305 -out "$certs_root_dir/root_ca.pem"
check_success "Failed to generate Root CA certificate"

# Create Root Certificate Authority Chain Bundle
print_section_header "Create Root Certificate Authority Chain Bundle"
cat "$certs_root_dir/root_ca.pem" "$certs_root_dir/trusted_id.pem" >"$certs_root_dir/root_ca_chain_bundle.pem"
check_success "Failed to create Root CA chain bundle"

# Function to verify certificates
verify_certificate() {
  openssl verify -CAfile "$1" "$2"
  check_success "Verification failed for $2"
}

# Perform certificate verifications
print_section_header "Verify Certificates"
verify_certificate "$certs_root_dir/root_ca_chain_bundle.pem" "$certs_root_dir/root_ca.pem"
verify_certificate "$certs_root_dir/trusted_id.pem" "$certs_root_dir/root_ca.pem"
verify_certificate "$certs_root_dir/trusted_id.pem" "$certs_root_dir/root_ca_chain_bundle.pem"

# Script completion message
echo
print_cyan "Certificate Authority process successfully completed."

exit 0
