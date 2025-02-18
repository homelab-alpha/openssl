#!/bin/bash

# Script Name: trusted_id.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-18T17:31:25+01:00
# Version: 2.5.0

# Description:
# This script generates and manages a trusted root certificate for a
# Certificate Authority. It sets up necessary directory paths, renews
# database serial numbers, generates an ECDSA key, creates a self-signed
# certificate, verifies the certificate, checks the private key, and
# converts the certificate to different formats.

# Usage: ./trusted_id.sh

# Notes:
# - Ensure you have the correct directory structure for certs and private keys.
# - Unique subject may cause issues if the Trusted ID already exists.
# - Overwriting the Trusted ID will require regeneration of the Root CA
#   and all issued certificates.

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

trusted_id_path="$certs_root_dir/trusted_id.pem"
trusted_id_exists=false
if [[ -f "$trusted_id_path" ]]; then
  trusted_id_exists=true
fi

# If unique_subject is enabled and Trusted ID exists, display an error and exit
if [[ "$unique_subject" == "yes" && "$trusted_id_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and Trusted ID already exists." >&2
  exit 1
fi

# If unique_subject is "no", warn and ask for confirmation
if [[ "$unique_subject" == "no" && -f "$trusted_id_path" ]]; then
  print_section_header "⚠️  WARNING: Overwriting Trusted ID"

  echo "[WARNING] Trusted ID already exists and will be OVERWRITTEN!" >&2
  echo "[WARNING] This action will require REGENERATING THE ROOT CA, ALL SUB-CA CERTIFICATES, AND ALL ISSUED CERTIFICATES!" >&2
  echo "[WARNING] If you continue, all issued certificates will become INVALID!" >&2

  read -p -r "Do you want to continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "[INFO] Operation aborted by user." >&2
    exit 1
  fi
fi

# Generate ECDSA key for Trusted ID
print_section_header "Generate ECDSA key for Trusted ID"
openssl ecparam -name secp384r1 -genkey -out "$private_root_dir/trusted_id.pem"
check_success "Failed to generate ECDSA key"

# Generate Certificate Signing Request (CSR) for Trusted ID
print_section_header "Generate Certificate Signing Request (CSR) for Trusted ID"
openssl req -new -x509 -sha384 -config "$openssl_conf_dir/trusted_id.cnf" -extensions v3_ca -key "$private_root_dir/trusted_id.pem" -days 10956 -out "$certs_root_dir/trusted_id.pem"
check_success "Failed to generate certificate"

# Verify Certificate against itself.
print_section_header "Verify Certificate against itself"
openssl verify -CAfile "$certs_root_dir/trusted_id.pem" "$certs_root_dir/trusted_id.pem"
check_success "Verification failed for certificate"

# Check Private Key.
print_section_header "Check Private Key"
openssl ecparam -in "$private_root_dir/trusted_id.pem" -text -noout
check_success "Failed to check private key"

# Check Certificate.
print_section_header "Check Certificate"
openssl x509 -in "$certs_root_dir/trusted_id.pem" -text -noout
check_success "Failed to check certificate"

# Convert Certificate from .pem to .crt.
print_section_header "Convert from trusted_id.pem to trusted_id.crt"
cp "$certs_root_dir/trusted_id.pem" "$certs_root_dir/trusted_id.crt"
check_success "Failed to convert certificate"

print_cyan "--> trusted_id.crt"

# Script completion message
echo
print_cyan "Certificate Authority process successfully completed."

exit 0
