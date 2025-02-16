#!/bin/bash

# Script Name: cert_ecdsa_server.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-16T12:08:42+01:00
# Version: 2.0.0

# Description:
# This script facilitates the creation of an ECDSA server certificate. It
# automates the process of generating the private key, creating a Certificate
# Signing Request (CSR), and issuing the final certificate. Additionally, it
# creates an extension file for certificate attributes, bundles the certificate
# with an intermediate CA chain, and performs several verification steps.
# The script also prepares a certificate bundle for use with HAProxy and converts
# the certificate into various formats for different applications.

# Usage: ./cert_ecdsa_server.sh

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
read -r -p "$(print_cyan "Enter the IPv4 address of the new certificate (syntax: , IP:192.168.x.x): ")" ipv4

# Define directory paths
print_section_header "Define directory paths"
ssl_dir="$HOME/ssl"
root_dir="$ssl_dir/root"
intermediate_dir="$ssl_dir/intermediate"
certificates_dir="$ssl_dir/certificates"
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
if grep -q "^unique_subject\s*=\s*yes" "$root_dir/db/index.txt.attr" "$intermediate_dir/db/index.txt.attr" "$tsa_dir/db/index.txt.attr" 2>/dev/null; then
  unique_subject="yes"
fi

cn_exists=false
if grep -q "CN=${fqdn}" "$root_dir/db/index.txt" "$intermediate_dir/db/index.txt" "$tsa_dir/db/index.txt" 2>/dev/null; then
  cn_exists=true
fi

if [[ "$unique_subject" == "yes" && "$cn_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and CSR with Common Name ${fqdn} already exists in index.txt" >&2
  exit 1
fi

# Generate ECDSA key
print_section_header "Generate ECDSA key"
openssl ecparam -name secp384r1 -genkey -out "$certificates_dir/private/${fqdn}.pem"
check_success "Failed to generate ECDSA key"

# Generate Certificate Signing Request (CSR)
print_section_header "Generate Certificate Signing Request (CSR)"
openssl req -new -sha384 -config "$certificates_dir/cert.cnf" -key "$certificates_dir/private/${fqdn}.pem" -out "$certificates_dir/csr/${fqdn}.pem"
check_success "Failed to generate CSR"

# Create an extfile with all the alternative names
print_section_header "Create an extfile with all the alternative names"
{
  echo "subjectAltName = DNS:${fqdn}, DNS:www.${fqdn}${ipv4}"
  echo "basicConstraints = critical, CA:FALSE"
  echo "keyUsage = critical, digitalSignature"
  echo "extendedKeyUsage = serverAuth"
  echo "nsCertType = server"
  echo "nsComment = OpenSSL Generated Server Certificate"
} >"$certificates_dir/extfile/${fqdn}.cnf"

# Generate Certificate
print_section_header "Generate Certificate"
openssl ca -config "$certificates_dir/cert.cnf" -notext -batch -in "$certificates_dir/csr/${fqdn}.pem" -out "$certificates_dir/certs/${fqdn}.pem" -extfile "$certificates_dir/extfile/${fqdn}.cnf"
check_success "Failed to generate certificate"

# Create Certificate Chain Bundle
print_section_header "Create Certificate Chain Bundle"
cat "$certificates_dir/certs/${fqdn}.pem" "$intermediate_dir/certs/ca_chain_bundle.pem" >"$certificates_dir/certs/${fqdn}_chain_bundle.pem"
check_success "Failed to create certificate chain bundle"

# Create Certificate Chain Bundle for HAProxy
print_section_header "Create Certificate Chain Bundle for HAProxy"
cat "$certificates_dir/certs/${fqdn}_chain_bundle.pem" "$certificates_dir/private/${fqdn}.pem" >"$certificates_dir/certs/${fqdn}_haproxy.pem"
chmod 600 "$certificates_dir/certs/${fqdn}_haproxy.pem"
check_success "Failed to create HAProxy certificate bundle"

# Function to verify certificates
verify_certificate() {
  openssl verify -CAfile "$1" "$2"
  check_success "Verification failed for $2"
}

# Perform certificate verifications
print_section_header "Verify Certificates"
verify_certificate "$certificates_dir/certs/${fqdn}_chain_bundle.pem" "$certificates_dir/certs/${fqdn}.pem"
verify_certificate "$intermediate_dir/certs/ca_chain_bundle.pem" "$certificates_dir/certs/${fqdn}.pem"
verify_certificate "$intermediate_dir/certs/ca_chain_bundle.pem" "$certificates_dir/certs/${fqdn}_chain_bundle.pem"
verify_certificate "$intermediate_dir/certs/ca_chain_bundle.pem" "$certificates_dir/certs/${fqdn}_haproxy.pem"

# Convert Certificate from .pem to .crt and .key
print_section_header "Convert Certificate Formats"
cp "$certificates_dir/certs/${fqdn}.pem" "$certificates_dir/certs/${fqdn}.crt"
cp "$certificates_dir/certs/${fqdn}_chain_bundle.pem" "$certificates_dir/certs/${fqdn}_chain_bundle.crt"
cp "$certificates_dir/private/${fqdn}.pem" "$certificates_dir/private/${fqdn}.key"
chmod 600 "$certificates_dir/private/${fqdn}.key"

print_cyan "--> ${fqdn}.crt"
print_cyan "--> ${fqdn}_chain_bundle.crt"
print_cyan "--> ${fqdn}.key"

exit 0
