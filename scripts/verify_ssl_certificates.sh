#!/bin/bash

# Script Name: verify_ssl_certificates.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-16T12:08:42+01:00
# Version: 2.0.0

# Description:
# This script verifies SSL/TLS certificates by checking them against their
# corresponding chain of trust. It performs various checks including verification
# of root, intermediate, and individual certificates.

# Usage: ./verify_ssl_certificates.sh [-v|--verbose] <certificate_name>

# Define directories
ssl_dir="$HOME/ssl"
root_dir="$ssl_dir/root/certs"
intermediate_dir="$ssl_dir/intermediate/certs"
certificates_dir="$ssl_dir/certificates/certs"

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

# Function to print usage information
print_usage() {
  echo "Usage: $0 [-v|--verbose] <certificate_name>"
  echo "  -v, --verbose    Enable verbose mode for detailed output during verification"
  echo "  <certificate_name> The name of the certificate to verify (e.g., root_ca.pem, ca.pem)"
  exit 1
}

# Function to check if a file exists
check_file_exists() {
  local file_path=$1
  if [ ! -f "$file_path" ]; then
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

  result=$(openssl verify -CAfile "$chain_path" "$cert_path" 2>&1)

  if [[ "$result" == *"OK"* ]]; then
    # Use actual ANSI escape codes to show color
    echo -e "$cert_path: \033[32m[ PASS ]\033[0m"
    # Show verbose output if enabled
    if [ "$verbose" = true ]; then
      echo -e "Verbose output: $result"
    fi
  else
    # For failure, display with red color
    echo -e "$cert_path: \033[31m[ FAIL ]\033[0m"
    # Show verbose output if enabled
    if [ "$verbose" = true ]; then
      echo -e "Verbose output: $result"
    fi
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
"trusted-id.pem")
  # Only verify the Trusted Identity certificate
  print_section_header "Verify Trusted Identity against Trusted Identity"
  verify_certificate "$root_dir/trusted-id.pem" "$root_dir/trusted-id.pem"
  ;;
"root_ca.pem")
  # Verify Trusted Identity certificate and Root Certificate Authority
  print_section_header "Verify Trusted Identity against Trusted Identity"
  verify_certificate "$root_dir/trusted-id.pem" "$root_dir/trusted-id.pem"

  print_section_header "Verify Root Certificate Authority against Trusted Identity"
  verify_certificate "$root_dir/root_ca.pem" "$root_dir/trusted-id.pem"

  print_section_header "Verify Root Certificate Authority Chain against Trusted Identity"
  verify_certificate "$root_dir/root_ca_chain_bundle.pem" "$root_dir/trusted-id.pem"
  ;;
"ca.pem")
  # Verify Trusted Identity certificate, Root Certificate Authority, and Intermediate Certificate Authority
  print_section_header "Verify Trusted Identity against Trusted Identity"
  verify_certificate "$root_dir/trusted-id.pem" "$root_dir/trusted-id.pem"

  print_section_header "Verify Root Certificate Authority against Trusted Identity"
  verify_certificate "$root_dir/root_ca.pem" "$root_dir/trusted-id.pem"

  print_section_header "Verify Root Certificate Authority Chain against Trusted Identity"
  verify_certificate "$root_dir/root_ca_chain_bundle.pem" "$root_dir/trusted-id.pem"

  print_section_header "Verify Intermediate Certificate Authority against the Root Certificate Authority"
  verify_certificate "$intermediate_dir/ca.pem" "$root_dir/root_ca_chain_bundle.pem"

  print_section_header "Verify Intermediate Certificate Authority Chain against the Root Certificate Authority Chain"
  verify_certificate "$intermediate_dir/ca_chain_bundle.pem" "$root_dir/root_ca_chain_bundle.pem"
  ;;
*)
  # If it's any other certificate (e.g., general certificate), verify everything
  print_section_header "Verify Trusted Identity against Trusted Identity"
  verify_certificate "$root_dir/trusted-id.pem" "$root_dir/trusted-id.pem"

  print_section_header "Verify Root Certificate Authority against Trusted Identity"
  verify_certificate "$root_dir/root_ca.pem" "$root_dir/trusted-id.pem"

  print_section_header "Verify Root Certificate Authority Chain against Trusted Identity"
  verify_certificate "$root_dir/root_ca_chain_bundle.pem" "$root_dir/trusted-id.pem"

  print_section_header "Verify Intermediate Certificate Authority against the Root Certificate Authority"
  verify_certificate "$intermediate_dir/ca.pem" "$root_dir/root_ca_chain_bundle.pem"

  print_section_header "Verify Intermediate Certificate Authority Chain against the Root Certificate Authority Chain"
  verify_certificate "$intermediate_dir/ca_chain_bundle.pem" "$root_dir/root_ca_chain_bundle.pem"

  print_section_header "Verify Certificate against the Certificate Chain"
  verify_certificate "$certificates_dir/${file_name}.pem" "$certificates_dir/${file_name}_chain_bundle.pem"

  print_section_header "Verify Certificate against the Intermediate Certificate Chain"
  verify_certificate "$certificates_dir/${file_name}.pem" "$intermediate_dir/ca_chain_bundle.pem"

  print_section_header "Verify Certificate Chain against the Intermediate Certificate Chain"
  verify_certificate "$certificates_dir/${file_name}_chain_bundle.pem" "$intermediate_dir/ca_chain_bundle.pem"

  print_section_header "Verify Haproxy Certificate Chain against the Intermediate Certificate Chain"
  verify_certificate "$certificates_dir/${file_name}_haproxy.pem" "$intermediate_dir/ca_chain_bundle.pem"
  ;;
esac

# Exit successfully
exit 0
