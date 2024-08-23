#!/bin/bash

# Script Name: root_ca.sh
# Author: GJS (homelab-alpha)
# Date: 2024-06-09T09:16:24+02:00
# Version: 1.0

# Description:
# This script sets up and manages a Root Certificate Authority (CA). It defines
# necessary directory paths, renews database serial numbers, generates ECDSA keys,
# creates Certificate Signing Requests (CSRs), and issues the root certificate.
# Additionally, it verifies the root certificate and creates a CA chain bundle,
# ensuring the integrity and correctness of the generated keys, CSRs, and certificates.

# Usage: ./root_ca.sh

# Function to print text in cyan color
print_cyan() {
  echo -e "\e[36m$1\e[0m" # \e[36m sets text color to cyan, \e[0m resets it
}

# Function to generate a random hex value.
generate_random_hex() {
  openssl rand -hex 16
}

# Function to print section headers.
print_section_header() {
  echo ""
  echo ""
  echo -e "$(print_cyan "=== $1 === ")"
}

# Define directory paths.
print_section_header "Define directory paths"
ssl_dir="$HOME/ssl"
root_dir="$ssl_dir/root"
intermediate_dir="$ssl_dir/intermediate"

# Renew db serial numbers.
print_section_header "Renew db serial numbers"
for dir in "$ssl_dir/root/db" "$intermediate_dir/db" "$ssl_dir/tsa/db"; do
  generate_random_hex >"$dir/serial"
done
generate_random_hex >"$ssl_dir/root/db/crlnumber"
generate_random_hex >"$intermediate_dir/db/crlnumber"

# Generate ECDSA key.
print_section_header "Generate ECDSA key"
openssl ecparam -name secp384r1 -genkey -out "$root_dir/private/root_ca.pem"

# Generate Certificate Signing Request (CSR).
print_section_header "Generate Certificate Signing Request (CSR)"
openssl req -new -sha384 -config "$root_dir/root_ca.cnf" -key "$root_dir/private/root_ca.pem" -out "$root_dir/csr/root_ca.pem"

# Generate Root Certificate Authority.
print_section_header "Generate Root Certificate Authority"
openssl ca -config "$root_dir/root_ca.cnf" -extensions v3_ca -notext -batch -in "$root_dir/csr/root_ca.pem" -days 7305 -out "$root_dir/certs/root_ca.pem"

# Create Root Certificate Authority Chain Bundle.
print_section_header "Create Root Certificate Authority Chain Bundle"
cat "$root_dir/certs/root_ca.pem" "$root_dir/certs/trusted-id.pem" >"$root_dir/certs/root_ca_chain_bundle.pem"

# Verify Root Certificate Authority against the Root Certificate Authority Chain Bundle.
print_section_header "Verify Root Certificate Authority against the Root Certificate Authority Chain Bundle"
openssl verify -CAfile "$root_dir/certs/root_ca_chain_bundle.pem" "$root_dir/certs/root_ca.pem"

# Verify Root Certificate Authority against Trusted Identity.
print_section_header "Verify Root Certificate Authority against Trusted Identity"
openssl verify -CAfile "$root_dir/certs/trusted-id.pem" "$root_dir/certs/root_ca.pem"

# Verify Root Certificate Authority Chain Bundle against Trusted Identity.
print_section_header "Verify Root Certificate Authority Chain Bundle against Trusted Identity"
openssl verify -CAfile "$root_dir/certs/trusted-id.pem" "$root_dir/certs/root_ca_chain_bundle.pem"

# Check Private Key.
print_section_header "Check Private Key"
openssl ecparam -in "$root_dir/private/root_ca.pem" -text -noout

# Check Certificate Signing Request (CSR).
print_section_header "Check Certificate Signing Request (CSR)"
openssl req -text -noout -verify -in "$root_dir/csr/root_ca.pem"

# Check Root Certificate Authority.
print_section_header "Check Root Certificate Authority"
openssl x509 -in "$root_dir/certs/root_ca.pem" -text -noout

# Check Root Certificate Authority Chain Bundle.
print_section_header "Check Root Certificate Authority Chain Bundle"
openssl x509 -in "$root_dir/certs/root_ca_chain_bundle.pem" -text -noout
