#!/bin/bash

# Script Name: verify_ssl_certificates.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-18T17:31:25+01:00
# Version: 2.5.0

# Description:
# This script automates the process of verifying SSL/TLS certificates by
# checking their validity against their corresponding chain of trust. The
# verification process includes the following steps:
# - Checking individual certificates against their root certificate authority.
# - Verifying intermediate certificates in the certificate chain.
# - Validating the certificate chain (from the leaf certificate up to the
#   root certificate).
#
# It provides both a verbose mode for detailed output and a non-verbose mode
# for summary results. Additionally, it supports certificate validation for
# various certificate types (Trusted Identity, Root, Intermediate, and general
# certificates).
#
# Usage: ./verify_ssl_certificates.sh [-v|--verbose] <certificate_name>
#
# Arguments:
#  -v, --verbose        Enable verbose mode for detailed output during
#                       verification.
#  <certificate_name>    The name of the certificate to verify (e.g.,
#                       root_ca.pem, ca.pem).

# Example usage:
#  - ./verify_ssl_certificates.sh root_ca.pem  (verifies root certificate
#    authority)
#  - ./verify_ssl_certificates.sh -v ca.pem    (verifies intermediate
#    certificate with verbose output)

# Set base directory
base_dir="$HOME/ssl"
certs_dir="$base_dir/certs"

# Set directories for various components
certs_certs_root_dir="$certs_dir/root"
certs_certs_intermediate_dir="$certs_dir/intermediate"
certs_certs_certificates_dir="$certs_dir/certificates"

# Default to non-verbose mode
verbose=false
file_name=""

# Function to print text in cyan color
print_cyan() {
  echo -e "\e[36m$1\e[0m"
}

# Function to print section headers.
print_section_header() {
  echo ""
  print_cyan "=== $1 ==="
}

# Function to check if a file exists
check_file_exists() {
  local file_path=$1
  if [ ! -f "$file_path" ]; then
    echo -e "$file_path: \033[31m[FAIL] - File not found\033[0m"
    return 1
  fi
  return 0
}

# Function to verify a certificate
verify_certificate() {
  local cert_path="$1"
  local chain_path="$2"

  # Check if files exist before verifying
  check_file_exists "$cert_path" || return
  check_file_exists "$chain_path" || return

  if [ "$verbose" = true ]; then
    result=$(openssl verify -show_chain -CAfile "$chain_path" "$cert_path" 2>&1)
  else
    result=$(openssl verify -CAfile "$chain_path" "$cert_path" 2>&1)
  fi

  if [[ "$result" == *"OK"* ]]; then
    echo -e "$cert_path: \033[32m[PASS]\033[0m"
  else
    echo -e "$cert_path: \033[31m[FAIL]\033[0m"
  fi

  # Show verbose output if enabled
  if [ "$verbose" = true ]; then
    echo -e "Verbose output: $result"
  fi
}

# Function to prompt for certificate file name if not passed as argument
prompt_for_file_name() {
  read -r -p "Enter the name of the certificate to verify: " file_name
}

# Function to parse arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -v | --verbose)
      verbose=true
      shift
      ;;
    *)
      file_name="$1"
      shift
      ;;
    esac
  done

  # If no file name is provided, prompt the user for it
  if [ -z "$file_name" ]; then
    prompt_for_file_name
  fi
}

# Main process

# Parse command-line options
parse_arguments "$@"

# Dynamically determine which sections to verify based on the certificate
case "$file_name" in
"trusted_id.pem")
  # Only verify the Trusted Identity certificate
  print_section_header "Verify Trusted Identity against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/trusted_id.pem" "$certs_certs_root_dir/trusted_id.pem"
  ;;
"root_ca.pem")
  # Verify Trusted Identity certificate and Root Certificate Authority
  print_section_header "Verify Trusted Identity against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/trusted_id.pem" "$certs_certs_root_dir/trusted_id.pem"

  print_section_header "Verify Root Certificate Authority against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/root_ca.pem" "$certs_certs_root_dir/trusted_id.pem"

  print_section_header "Verify Root Certificate Authority Chain against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/root_ca_chain_bundle.pem" "$certs_certs_root_dir/trusted_id.pem"
  ;;
"ca.pem")
  # Verify Trusted Identity certificate, Root Certificate Authority, and Intermediate Certificate Authority
  print_section_header "Verify Trusted Identity against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/trusted_id.pem" "$certs_certs_root_dir/trusted_id.pem"

  print_section_header "Verify Root Certificate Authority against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/root_ca.pem" "$certs_certs_root_dir/trusted_id.pem"

  print_section_header "Verify Root Certificate Authority Chain against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/root_ca_chain_bundle.pem" "$certs_certs_root_dir/trusted_id.pem"

  print_section_header "Verify Intermediate Certificate Authority against the Root Certificate Authority"
  verify_certificate "$certs_certs_intermediate_dir/ca.pem" "$certs_certs_root_dir/root_ca_chain_bundle.pem"

  print_section_header "Verify Intermediate Certificate Authority Chain against the Root Certificate Authority Chain"
  verify_certificate "$certs_certs_intermediate_dir/ca_chain_bundle.pem" "$certs_certs_root_dir/root_ca_chain_bundle.pem"
  ;;
*)
  # If it's any other certificate (e.g., general certificate), verify everything
  print_section_header "Verify Trusted Identity against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/trusted_id.pem" "$certs_certs_root_dir/trusted_id.pem"

  print_section_header "Verify Root Certificate Authority against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/root_ca.pem" "$certs_certs_root_dir/trusted_id.pem"

  print_section_header "Verify Root Certificate Authority Chain against Trusted Identity"
  verify_certificate "$certs_certs_root_dir/root_ca_chain_bundle.pem" "$certs_certs_root_dir/trusted_id.pem"

  print_section_header "Verify Intermediate Certificate Authority against the Root Certificate Authority"
  verify_certificate "$certs_certs_intermediate_dir/ca.pem" "$certs_certs_root_dir/root_ca_chain_bundle.pem"

  print_section_header "Verify Intermediate Certificate Authority Chain against the Root Certificate Authority Chain"
  verify_certificate "$certs_certs_intermediate_dir/ca_chain_bundle.pem" "$certs_certs_root_dir/root_ca_chain_bundle.pem"

  print_section_header "Verify Certificate against the Certificate Chain"
  verify_certificate "$certs_certs_certificates_dir/${file_name}.pem" "$certs_certs_certificates_dir/${file_name}_chain_bundle.pem"

  print_section_header "Verify Certificate against the Intermediate Certificate Chain"
  verify_certificate "$certs_certs_certificates_dir/${file_name}.pem" "$certs_certs_intermediate_dir/ca_chain_bundle.pem"

  print_section_header "Verify Certificate Chain against the Intermediate Certificate Chain"
  verify_certificate "$certs_certs_certificates_dir/${file_name}_chain_bundle.pem" "$certs_certs_intermediate_dir/ca_chain_bundle.pem"

  print_section_header "Verify Haproxy Certificate Chain against the Intermediate Certificate Chain"
  verify_certificate "$certs_certs_certificates_dir/${file_name}_haproxy.pem" "$certs_certs_intermediate_dir/ca_chain_bundle.pem"
  ;;
esac

# Exit successfully
exit 0
