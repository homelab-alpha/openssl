#!/bin/bash

# Define directories
certificates_dir="$HOME/ssl/certificates/certs"
intermediate_dir="$HOME/ssl/intermediate/certs"
root_dir="${HOME}/ssl/root/certs"

# Default to non-verbose mode
verbose=false

# Function to print section headers.
print_section_header() {
  echo ""
  echo ""
  echo -e "\e[38;2;102;204;204m=== $1 ===\e[0m"
}

# Function to print usage information
print_usage() {
  echo "Usage: $0 [-v|--verbose]"
  echo "  -v, --verbose    Enable verbose mode for detailed output during verification"
  exit 1
}

# Function to perform certificate verification
verify_certificate() {
  local cert_path="$1"
  local chain_path="$2"

  # Print verification header
  # echo -e "\nVerifying $cert_path against $chain_path:"
  echo "Verifying $cert_path against $chain_path:"

  # Run openssl command and capture the result
  result=$(openssl verify -CAfile "$chain_path" "$cert_path" 2>&1)

  # Check the result and print in color
  if [[ "$result" == *"OK"* ]]; then
    ok_part=$(echo "$result" | grep -o "OK")
    result_colored="${result/OK/$'\e[32m'$ok_part$'\e[0m'}"
    echo -e "$result_colored"
  else
    echo -e "$result"
  fi

  # Print verbose information if enabled
  if [ "$verbose" = true ]; then
    echo -e "\nVerbose Information:"
    openssl x509 -noout -text -in "$cert_path"
  fi
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
  -v | --verbose)
    verbose=true
    shift
    ;;
  *)
    print_usage
    ;;
  esac
done

# Prompt user for the certificate name
read -r -p "Enter the name of the certificate to verify: " file_name

# Verify Trusted Identity against Trusted Identity.
print_section_header "Verify Trusted Identity against Trusted Identity"
verify_certificate "$root_dir/trusted-id.pem" "$root_dir/trusted-id.pem"

# Verify Root Certificate Authority against Trusted Identity.
print_section_header "Verify Root Certificate Authority against Trusted Identity"
verify_certificate "$root_dir/root_ca.pem" "$root_dir/trusted-id.pem"

# Verify Root Certificate Authority Chain against Trusted Identity.
print_section_header "Verify Root Certificate Authority Chain against Trusted Identity"
verify_certificate "$root_dir/root_ca_chain_bundle.pem" "$root_dir/trusted-id.pem"

# Verify Intermediate Certificate Authority against the Root Certificate Authority.
print_section_header "Verify Intermediate Certificate Authority against the Root Certificate Authority"
verify_certificate "$intermediate_dir/ca.pem" "$root_dir/root_ca_chain_bundle.pem"

# Verify Intermediate Certificate Authority Chain against the Root Certificate Authority Chain.
print_section_header "Verify Intermediate Certificate Authority Chain against the Root Certificate Authority Chain"
verify_certificate "$intermediate_dir/ca_chain_bundle.pem" "$root_dir/root_ca_chain_bundle.pem"

# Verify Certificate against the Certificate Chain.
print_section_header "Verify Certificate against the Certificate Chain"
verify_certificate "$certificates_dir/${file_name}.pem" "$certificates_dir/${file_name}_chain_bundle.pem"

# Verify Certificate against the Intermediate Certificate Chain.
print_section_header "Verify Certificate against the Intermediate Certificate Chain"
verify_certificate "$certificates_dir/${file_name}.pem" "$intermediate_dir/ca_chain_bundle.pem"

# Verify Certificate Chain against the Intermediate Certificate Chain.
print_section_header "Verify Certificate Chain against the Intermediate Certificate Chain"
verify_certificate "$certificates_dir/${file_name}_chain_bundle.pem" "$intermediate_dir/ca_chain_bundle.pem"

# Verify Haproxy Certificate Chain against the Intermediate Certificate Chain.
print_section_header "Verify Haproxy Certificate Chain against the Intermediate Certificate Chain"
verify_certificate "$certificates_dir/${file_name}_haproxy.pem" "$intermediate_dir/ca_chain_bundle.pem"

# Additional verifications based on user input can be added here.

# Exit successfully
exit 0
