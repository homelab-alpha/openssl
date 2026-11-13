#!/bin/bash

# Script Name: verify_tls_certificates.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 3.0.0

# Description:
# This script verifies TLS certificates against their chain of trust:
# - The trusted identity against itself.
# - The root certificate authority against the trusted identity.
# - The intermediate certificate authority against the root chain.
# - A server or client certificate against the intermediate chain, and its
#   chain bundle and HAProxy bundle when they exist.
#
# The result of each check comes from the exit status of openssl verify. The
# script never changes a file.
#
# Usage: ./verify_tls_certificates.sh [-v|--verbose] [-h|--help] <certificate_name>
#
# Arguments:
#  -v, --verbose        Show the output of openssl verify for each check.
#  -h, --help           Show this help.
#  <certificate_name>   The certificate to verify: trusted_id.pem,
#                       root_ca.pem, ca.pem, or the name of a server or
#                       client certificate without extension (for example
#                       server.example.test).

# Example usage:
#  - ./verify_tls_certificates.sh root_ca.pem  (verifies root certificate
#    authority)
#  - ./verify_tls_certificates.sh -v ca.pem    (verifies intermediate
#    certificate with verbose output)

# Exit codes:
#  0  All checks passed.
#  1  One or more checks failed, or a file was not found.
#  2  Wrong usage.

# Stop script on error. The functions below return a status on purpose, and
# the callers decide what a failure means.
set -Eeuo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh" || exit 2

# Set the base directory. The old name ~/ssl is used while ~/tls does not exist.
set_base_dir
certs_dir="$base_dir/certs"

# Set directories for various components
certs_root_dir="$certs_dir/root"
certs_intermediate_dir="$certs_dir/intermediate"
certs_certificates_dir="$certs_dir/certificates"

# Default to non-verbose mode
verbose=false
file_name=""
failures=0

# Function to verify a certificate against a chain file
verify_certificate() {
  local title="$1" cert_path="$2" chain_path="$3" result status=0 file options=()

  print_section_header "$title"
  for file in "$cert_path" "$chain_path"; do
    if [[ ! -f "$file" ]]; then
      echo -e "$file: \033[31m[FAIL] - File not found\033[0m"
      failures=$((failures + 1))
      return
    fi
  done

  [[ "$verbose" == "false" ]] || options=(-show_chain)
  result=$(openssl verify ${options[@]+"${options[@]}"} -CAfile "$chain_path" "$cert_path" 2>&1) || status=$?

  if [[ "$status" -eq 0 ]]; then
    echo -e "$cert_path: \033[32m[PASS]\033[0m"
  else
    echo -e "$cert_path: \033[31m[FAIL]\033[0m"
    failures=$((failures + 1))
  fi

  # Show verbose output if enabled, and always for a failed check
  if [[ "$verbose" == "true" || "$status" -ne 0 ]]; then
    echo "$result"
  fi
}

# Function to parse arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -v | --verbose)
      verbose=true
      shift
      ;;
    -h | --help)
      show_usage '^# Example usage:'
      exit 0
      ;;
    -*)
      print_error "Unknown option: $1"
      exit 2
      ;;
    *)
      [[ -z "$file_name" ]] || {
        print_error "Give only one certificate name."
        exit 2
      }
      file_name="$1"
      shift
      ;;
    esac
  done

  # If no file name is provided, prompt the user for it
  if [[ -z "$file_name" ]]; then
    read -r -p "Enter the name of the certificate to verify: " file_name || true
  fi
  if [[ -z "$file_name" || "$file_name" == */* ]]; then
    print_error "'$file_name' is not a certificate name."
    exit 2
  fi
}

# Function to check that a bundle holds a complete chain: the certificate is
# verified with only the trusted identity as trust anchor and the certificates
# of the bundle as the chain in between. openssl verify on the bundle itself
# would only look at its first certificate.
verify_bundle() {
  local title="$1" cert_path="$2" bundle_path="$3" anchor="$certs_root_dir/trusted_id.pem" result status=0 file

  print_section_header "$title"
  for file in "$cert_path" "$bundle_path" "$anchor"; do
    if [[ ! -f "$file" ]]; then
      echo -e "$file: \033[31m[FAIL] - File not found\033[0m"
      failures=$((failures + 1))
      return
    fi
  done

  result=$(openssl verify -CAfile "$anchor" -untrusted "$bundle_path" "$cert_path" 2>&1) || status=$?
  # The bundle must start with the certificate itself
  if [[ "$status" -eq 0 ]] && [[ "$(openssl x509 -in "$bundle_path" -noout -fingerprint -sha256 2>/dev/null)" != \
  "$(openssl x509 -in "$cert_path" -noout -fingerprint -sha256 2>/dev/null)" ]]; then
    status=1
    result="The bundle does not start with the certificate."
  fi

  if [[ "$status" -eq 0 ]]; then
    echo -e "$bundle_path: \033[32m[PASS]\033[0m"
  else
    echo -e "$bundle_path: \033[31m[FAIL]\033[0m"
    failures=$((failures + 1))
  fi
  if [[ "$verbose" == "true" || "$status" -ne 0 ]]; then
    echo "$result"
  fi
}

# Function to check that the private key in a HAProxy bundle belongs to the
# certificate
verify_bundle_key() {
  local title="$1" cert_path="$2" bundle_path="$3"

  print_section_header "$title"
  if [[ "$(openssl pkey -in "$bundle_path" -pubout 2>/dev/null)" == "$(openssl x509 -in "$cert_path" -noout -pubkey 2>/dev/null)" ]]; then
    echo -e "$bundle_path: \033[32m[PASS]\033[0m"
  else
    echo -e "$bundle_path: \033[31m[FAIL]\033[0m"
    echo "The private key in the bundle does not match the certificate, or the bundle cannot be read."
    failures=$((failures + 1))
  fi
}

# Functions to verify each level of the chain
verify_trusted_id() {
  verify_certificate "Verify Trusted Identity against Trusted Identity" \
    "$certs_root_dir/trusted_id.pem" "$certs_root_dir/trusted_id.pem"
}

verify_root_ca() {
  verify_certificate "Verify Root Certificate Authority against Trusted Identity" \
    "$certs_root_dir/root_ca.pem" "$certs_root_dir/trusted_id.pem"
  verify_bundle "Verify the chain in the Root Certificate Authority Chain Bundle" \
    "$certs_root_dir/root_ca.pem" "$certs_root_dir/root_ca_chain_bundle.pem"
}

verify_intermediate_ca() {
  verify_certificate "Verify Intermediate Certificate Authority against the Root Certificate Authority" \
    "$certs_intermediate_dir/ca.pem" "$certs_root_dir/root_ca_chain_bundle.pem"
  verify_bundle "Verify the chain in the Intermediate Certificate Authority Chain Bundle" \
    "$certs_intermediate_dir/ca.pem" "$certs_intermediate_dir/ca_chain_bundle.pem"
}

verify_leaf() {
  local name="$1"
  verify_certificate "Verify Certificate against the Intermediate Certificate Chain" \
    "$certs_certificates_dir/${name}.pem" "$certs_intermediate_dir/ca_chain_bundle.pem"
  verify_bundle "Verify the chain in the Certificate Chain Bundle" \
    "$certs_certificates_dir/${name}.pem" "$certs_certificates_dir/${name}_chain_bundle.pem"
  # Only server certificates have a HAProxy bundle
  if [[ -f "$certs_certificates_dir/${name}_haproxy.pem" ]]; then
    verify_bundle "Verify the chain in the HAProxy Bundle" \
      "$certs_certificates_dir/${name}.pem" "$certs_certificates_dir/${name}_haproxy.pem"
    verify_bundle_key "Verify the private key in the HAProxy Bundle" \
      "$certs_certificates_dir/${name}.pem" "$certs_certificates_dir/${name}_haproxy.pem"
  fi
}

# Main process
parse_arguments "$@"
require_openssl 2

# Determine which sections to verify based on the certificate
case "$file_name" in
"trusted_id.pem")
  verify_trusted_id
  ;;
"root_ca.pem")
  verify_trusted_id
  verify_root_ca
  ;;
"ca.pem")
  verify_trusted_id
  verify_root_ca
  verify_intermediate_ca
  ;;
*)
  verify_trusted_id
  verify_root_ca
  verify_intermediate_ca
  verify_leaf "${file_name%.pem}"
  ;;
esac

echo
if [[ "$failures" -gt 0 ]]; then
  print_error "$failures check(s) failed."
  exit 1
fi
print_cyan "All checks passed."
exit 0
