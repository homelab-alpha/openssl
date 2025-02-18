#!/bin/bash

# Script Name: ssl_directory_setup.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-18T17:31:25+01:00
# Version: 2.5.0

# Description:
# This script sets up the directory structure for SSL certificate management.
# It generates random serial numbers for certificate databases and creates
# OpenSSL configuration files for a trusted identity (root certificate
# authority) and time-stamping authority (TSA). Requires OpenSSL and write
# permissions in the specified directories.

# Usage:
# Run the script directly without any arguments:
# ./ssl_directory_setup.sh

# Notes:
# - Ensure OpenSSL is installed before running the script.
# - The script creates directories and files under $HOME/ssl.
# - The OpenSSL configuration directory is assumed to be at $HOME/openssl.

# Function to check if OpenSSL is installed
check_openssl_installed() {
  if ! command -v openssl &>/dev/null; then
    echo "Error: OpenSSL is not installed. Please install it before running this script."
    exit 1 # Stop the script with an error code
  fi
}

# Function to print text in cyan color
print_cyan() {
  echo -e "\e[36m$1\e[0m"
}

# Function to generate a random hex value
generate_random_hex() {
  openssl rand -hex 16 || {
    echo "Error: Failed to generate random hex."
    exit 1
  }
}

# Function to print section headers
print_section_header() {
  echo ""
  print_cyan "=== $1 ==="
}

# Set base directory
base_dir="$HOME/ssl"
certs_dir="$base_dir/certs"
crl_dir="$base_dir/crl"
crl_backup_dir="$base_dir/crl-backup"
csr_dir="$base_dir/csr"
extfile_dir="$base_dir/extfiles"
newcerts_dir="$base_dir/newcerts"
private_dir="$base_dir/private"
db_dir="$base_dir/db"
log_dir="$base_dir/log"
openssl_conf_dir="$base_dir/openssl.cnf"
tsa_dir="$base_dir/tsa"

# Set directories for various components (save keeping)
# certs_root_dir="$certs_dir/root"
# certs_intermediate_dir="$certs_dir/intermediate"
# certs_certificates_dir="$certs_dir/certificates"
# private_root_dir="$private_dir/root"
# private_intermediate_dir="$private_dir/intermediate"
# private_certificates_dir="$private_dir/certificates"
# tsa_certs_dir="$tsa_dir/certs"
# tsa_private_dir="$tsa_dir/private"

# Create directory structure.
print_section_header "Creating directory structure"
mkdir -p "$certs_dir"/{root,intermediate,certificates} \
  "$crl_dir" \
  "$crl_backup_dir" \
  "$csr_dir" \
  "$extfile_dir" \
  "$newcerts_dir" \
  "$private_dir"/{root,intermediate,certificates} \
  "$db_dir" \
  "$log_dir" \
  "$openssl_conf_dir" \
  "$tsa_dir"/{certs,private,db}

# Create db files and set unique_subject attribute.
print_section_header "Creating db files and setting unique_subject attribute"
touch "$db_dir/index.txt"
touch "$tsa_dir/db/index.txt"

for dir in "$db_dir" "$tsa_dir/db"; do
  touch "$dir/index.txt.attr"
  echo "unique_subject = yes" >"$dir/index.txt.attr"
done

# Renew db numbers (serial and CRL) in one loop.
print_section_header "Renewing db numbers (serial and CRL)"
for type in "serial" "crlnumber"; do
  for dir in "$db_dir" "$tsa_dir/db"; do
    generate_random_hex >"$dir/$type"
  done
done

# Copy OpenSSL configuration files to the target directory
print_section_header "Copying OpenSSL configuration files"
if [ -d "$HOME/openssl/openssl.cnf" ]; then
  cp -r "$HOME/openssl/openssl.cnf"/* "$openssl_conf_dir/"
else
  echo "Warning: OpenSSL configuration directory not found at $HOME/openssl/openssl.cnf."
  echo "Skipping OpenSSL configuration files copy."
fi

# Script completion message
echo
print_cyan "SSL directory setup completed successfully."
