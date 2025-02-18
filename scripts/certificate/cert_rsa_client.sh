#!/bin/bash

# Script Name: cert_rsa_client.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-18T17:31:25+01:00
# Version: 2.5.0

# Description:
# This script automates the creation of an RSA client certificate. It handles
# the generation of the private key, creation of a CSR, and issues the final
# certificate. The script also creates an extension file for certificate
# attributes, bundles the certificate with an intermediate CA chain, and
# verifies the certificate. It converts the certificate into various formats
# suitable for different applications.

# Usage: ./cert_rsa_client.sh

# Notes:
# - Ensure OpenSSL is installed and configured for the process to work.
# - The script creates certificate files in the $HOME/ssl directory.
# - The certificate is generated with the Common Name (CN) specified by the user.
# - It checks for an existing CN in the index.txt before proceeding.
# - The final output includes .crt, .key, and .chain_bundle.crt files.

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

# Certificate information
read -r -p "$(print_cyan "Enter the FQDN name of the new certificate: ")" fqdn

# Define directory paths
print_section_header "Define directory paths"
base_dir="$HOME/ssl"
certs_dir="$base_dir/certs"
csr_dir="$base_dir/csr"
extfile_dir="$base_dir/extfiles"
private_dir="$base_dir/private"
db_dir="$base_dir/db"
openssl_conf_dir="$base_dir/openssl.cnf"

# Set directories for various components
certs_intermediate_dir="$certs_dir/intermediate"
certs_certificates_dir="$certs_dir/certificates"
private_certificates_dir="$private_dir/certificates"

# Renew db numbers (serial and CRL)
print_section_header "Renew db numbers (serial and CRL)"
for type in "serial" "crlnumber"; do
  for dir in $db_dir; do
    generate_random_hex >"$dir/$type" || check_success "Failed to generate $type for $dir"
  done
done

# Check if unique_subject is enabled and if CN exists
unique_subject="no"
if grep -q "^unique_subject\s*=\s*yes" "$db_dir/index.txt.attr" 2>/dev/null; then
  unique_subject="yes"
fi

cn_exists=false
if grep -q "CN=${fqdn}" "$db_dir/index.txt" 2>/dev/null; then
  cn_exists=true
fi

if [[ "$unique_subject" == "yes" && "$cn_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and CSR with Common Name ${fqdn} already exists in index.txt" >&2
  exit 1
fi

# Generate RSA key
print_section_header "Generate RSA key"
openssl genrsa -out "$private_certificates_dir/${fqdn}.pem"
check_success "Failed to generate RSA key"

# Generate Certificate Signing Request (CSR)
print_section_header "Generate Certificate Signing Request (CSR)"
openssl req -new -sha256 -config "$openssl_conf_dir/cert.cnf" -key "$private_certificates_dir/${fqdn}.pem" -out "$csr_dir/${fqdn}.pem"
check_success "Failed to generate CSR"

# Create an extfile with all the alternative names
print_section_header "Create an extfile with all the alternative names"
{
  echo "subjectAltName = DNS:${fqdn}, DNS:www.${fqdn}"
  echo "basicConstraints = critical, CA:FALSE"
  echo "keyUsage = critical, digitalSignature"
  echo "extendedKeyUsage = clientAuth, emailProtection"
  echo "nsCertType = client, email"
  echo "nsComment = OpenSSL Generated Client Certificate"
} >"$extfile_dir/${fqdn}.cnf"

# Generate Certificate
print_section_header "Generate Certificate"
openssl ca -config "$openssl_conf_dir/cert.cnf" -notext -batch -in "$csr_dir/${fqdn}.pem" -out "$certs_certificates_dir/${fqdn}.pem" -extfile "$extfile_dir/${fqdn}.cnf"
check_success "Failed to generate certificate"

# Create Certificate Chain Bundle
print_section_header "Create Certificate Chain Bundle"
cat "$certs_certificates_dir/${fqdn}.pem" "$certs_intermediate_dir/ca_chain_bundle.pem" >"$certs_certificates_dir/${fqdn}_chain_bundle.pem"
check_success "Failed to create certificate chain bundle"

# Perform certificate verifications
print_section_header "Verify Certificates"
verify_certificate() {
  openssl verify -CAfile "$1" "$2"
  check_success "Verification failed for $2"
}

verify_certificate "$certs_certificates_dir/${fqdn}_chain_bundle.pem" "$certs_certificates_dir/${fqdn}.pem"
verify_certificate "$certs_intermediate_dir/ca_chain_bundle.pem" "$certs_certificates_dir/${fqdn}.pem"
verify_certificate "$certs_intermediate_dir/ca_chain_bundle.pem" "$certs_certificates_dir/${fqdn}_chain_bundle.pem"

# Convert Certificate from .pem to .crt and .key
print_section_header "Convert Certificate Formats"
cp "$certs_certificates_dir/${fqdn}.pem" "$certs_certificates_dir/${fqdn}.crt"
cp "$certs_certificates_dir/${fqdn}_chain_bundle.pem" "$certs_certificates_dir/${fqdn}_chain_bundle.crt"
cp "$private_certificates_dir/${fqdn}.pem" "$private_certificates_dir/${fqdn}.key"
chmod 600 "$private_certificates_dir/${fqdn}.key"

print_cyan "--> ${fqdn}.crt"
print_cyan "--> ${fqdn}_chain_bundle.crt"
print_cyan "--> ${fqdn}.key"

# Script completion message
echo
print_cyan "Certificate process completed successfully."

exit 0
