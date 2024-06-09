#!/bin/bash

# Script Name: ca.sh
# Author: GJS (homelab-alpha)
# Date: 2024-06-09T09:16:27+02:00
# Version: 1.0.1

# Description:
# This script facilitates the setup and management of an Intermediate Certificate
# Authority (CA). It defines directory paths, renews database serial numbers,
# generates ECDSA keys, creates Certificate Signing Requests (CSRs), and issues
# the intermediate certificate. The script also creates and verifies the
# intermediate CA chain bundle, ensuring the validity and integrity of the
# generated keys, CSRs, and certificates.

# Usage: ./ca.sh

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
openssl ecparam -name secp384r1 -genkey -out "$intermediate_dir/private/ca.pem"

# Generate Certificate Signing Request (CSR).
print_section_header "Generate Certificate Signing Request (CSR)"
openssl req -new -sha384 -config "$intermediate_dir/ca.cnf" -key "$intermediate_dir/private/ca.pem" -out "$intermediate_dir/csr/ca.pem"

# Generate Intermediate Certificate Authority.
print_section_header "Generate Intermediate Certificate Authority"
openssl ca -config "$intermediate_dir/ca.cnf" -extensions v3_intermediate_ca -notext -batch -in "$intermediate_dir/csr/ca.pem" -days 1826 -out "$intermediate_dir/certs/ca.pem"

# Create Intermediate Certificate Authority Chain Bundle.
print_section_header "Create Intermediate Certificate Authority Chain Bundle"
cat "$intermediate_dir/certs/ca.pem" "$root_dir/certs/root_ca_chain_bundle.pem" >"$intermediate_dir/certs/ca_chain_bundle.pem"

# Verify Intermediate Certificate Authority against the Intermediate Certificate Authority Chain Bundle.
print_section_header "Verify Intermediate Certificate Authority against the Intermediate Certificate Authority Chain Bundle"
openssl verify -CAfile "$intermediate_dir/certs/ca_chain_bundle.pem" "$intermediate_dir/certs/ca.pem"

# Verify Intermediate Certificate Authority against Root Certificate Authority Chain Bundle.
print_section_header "Verify Intermediate Certificate Authority against Root Certificate Authority Chain Bundle"
openssl verify -CAfile "$root_dir/certs/root_ca_chain_bundle.pem" "$intermediate_dir/certs/ca.pem"

# Verify Intermediate Certificate Authority Chain Bundle against Root Certificate Authority Chain Bundle.
print_section_header "Verify Intermediate Certificate Authority Chain Bundle against Root Certificate Authority Chain Bundle"
openssl verify -CAfile "$root_dir/certs/root_ca_chain_bundle.pem" "$intermediate_dir/certs/ca_chain_bundle.pem"

# Check Private Key.
print_section_header "Check Private Key"
openssl ecparam -in "$intermediate_dir/private/ca.pem" -text -noout

# Check Certificate Signing Request (CSR).
print_section_header "Check Certificate Signing Request (CSR)"
openssl req -text -noout -verify -in "$intermediate_dir/csr/ca.pem"

# Check Intermediate Certificate Authority.
print_section_header "Check Intermediate Certificate Authority"
openssl x509 -in "$intermediate_dir/certs/ca.pem" -text -noout

# Check Intermediate Certificate Authority Chain Bundle.
print_section_header "Check Intermediate Certificate Authority Chain Bundle"
openssl x509 -in "$intermediate_dir/certs/ca_chain_bundle.pem" -text -noout
