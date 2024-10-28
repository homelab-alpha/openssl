#!/bin/bash

# Script Name: cert_ecdsa_client.sh
# Author: GJS (homelab-alpha)
# Date: 2024-10-28T10:37:39+01:00
# Version: 1.1.0

# Description:
# This script generates an ECDSA client certificate, including the creation of
# the necessary private key, Certificate Signing Request (CSR), and the final
# certificate. It also creates an extension file for additional certificate
# parameters, bundles the certificate with an intermediate CA chain, and verifies
# the generated certificate and its chain bundle. Finally, it converts the
# certificate into different formats for various uses.

# Usage: ./cert_ecdsa_client.sh

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

# Prompt for Certificate information.
read -r -p "$(print_cyan "Enter the FQDN name of the new certificate: ")" fqdn

# Define directory paths.
print_section_header "Define directory paths"
ssl_dir="$HOME/ssl"
certificates_dir="$ssl_dir/certificates"
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
openssl ecparam -name secp384r1 -genkey -out "$certificates_dir/private/${fqdn}.pem"

# Generate Certificate Signing Request (CSR).
print_section_header "Generate Certificate Signing Request (CSR)"
openssl req -new -sha384 -config "$certificates_dir/cert.cnf" -key "$certificates_dir/private/${fqdn}.pem" -out "$certificates_dir/csr/${fqdn}.pem"

# Create an extfile with all the alternative names.
print_section_header "Create an extfile with all the alternative names"
{
  echo "basicConstraints = critical, CA:FALSE"
  echo "keyUsage = critical, digitalSignature"
  echo "extendedKeyUsage = clientAuth, emailProtection"
  echo "nsCertType = client, email"
  echo "nsComment = OpenSSL Generated Server Certificate"
} >>"$certificates_dir/extfile/${fqdn}.cnf"

# Generate Certificate.
print_section_header "Generate Certificate"
openssl ca -config "$certificates_dir/cert.cnf" -notext -batch -in "$certificates_dir/csr/${fqdn}.pem" -out "$certificates_dir/certs/${fqdn}.pem" -extfile "$certificates_dir/extfile/${fqdn}.cnf"

# Create Certificate Chain Bundle.
print_section_header "Create Certificate Chain Bundle"
cat "$certificates_dir/certs/${fqdn}.pem" "$intermediate_dir/certs/ca_chain_bundle.pem" >"$certificates_dir/certs/${fqdn}_chain_bundle.pem"

# Verify Certificate against the Certificate Chain Bundle.
print_section_header "Verify ${fqdn} Certificate against the ${fqdn} Certificate Chain Bundle"
openssl verify -CAfile "$certificates_dir/certs/${fqdn}_chain_bundle.pem" "$certificates_dir/certs/${fqdn}.pem"

# Verify Certificate against the Intermediate Certificate Authority Chain Bundle.
print_section_header "Verify ${fqdn} Certificate against the Intermediate Certificate Authority Chain Bundle"
openssl verify -CAfile "$intermediate_dir/certs/ca_chain_bundle.pem" "$certificates_dir/certs/${fqdn}.pem"

# Verify Certificate Chain Bundle against the Intermediate Certificate Authority Chain Bundle.
print_section_header "Verify ${fqdn} Certificate Chain Bundle against the Intermediate Certificate Authority Chain Bundle"
openssl verify -CAfile "$intermediate_dir/certs/ca_chain_bundle.pem" "$certificates_dir/certs/${fqdn}_chain_bundle.pem"

# Check Private Key.
print_section_header "Check Private Key"
openssl ecparam -in "$certificates_dir/private/${fqdn}.pem" -text -noout

# Check Certificate Signing Request (CSR).
print_section_header "Check Certificate Signing Request (CSR)"
openssl req -text -noout -verify -in "$certificates_dir/csr/${fqdn}.pem"

# Check Certificate.
print_section_header "Check Certificate"
openssl x509 -in "$certificates_dir/certs/${fqdn}.pem" -text -noout

# Check Certificate Chain Bundle.
print_section_header "Check Certificate Chain Bundle"
openssl x509 -in "$certificates_dir/certs/${fqdn}_chain_bundle.pem" -text -noout

# Convert Certificate from .pem to .crt and .key.
print_section_header "Convert Certificate from ${fqdn}.pem to"
cat "$certificates_dir/certs/${fqdn}.pem" >"$certificates_dir/certs/${fqdn}.crt"
cat "$certificates_dir/certs/${fqdn}_chain_bundle.pem" >"$certificates_dir/certs/${fqdn}_chain_bundle.crt"
cat "$certificates_dir/private/${fqdn}.pem" >"$certificates_dir/private/${fqdn}.key"
chmod 600 "$certificates_dir/private/${fqdn}.key"
echo -e "$(print_cyan "--> ")""${fqdn}.crt"
echo -e "$(print_cyan "--> ")""${fqdn}_chain_bundle.crt"
echo -e "$(print_cyan "--> ")""${fqdn}.key"
