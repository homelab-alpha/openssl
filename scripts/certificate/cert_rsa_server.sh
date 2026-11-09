#!/bin/bash

# Script Name: cert_rsa_server.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-09T10:00:00+01:00
# Version: 2.7.0

# Description:
# This script automates the creation and management of RSA certificates
# for server authentication. It sets up necessary directories, renews
# database serial numbers, generates RSA keys, creates Certificate
# Signing Requests (CSRs), and certificates. It verifies generated
# certificates and creates certificate chain bundles for services
# like HAProxy. The script also checks the integrity and details of
# generated keys, CSRs, and certificates.

# Usage: ./cert_rsa_server.sh [--fqdn <fqdn> [--ip <ipv4>]] [--reuse-key] [-h|--help]
#
# Options:
#  --fqdn <fqdn> Run without questions for this FQDN. The Common Name is
#                set to the FQDN, so it is not asked a second time.
#  --ip <ipv4>   Add this IPv4 address to the subject alternative names.
#                Only used together with --fqdn.
#  --reuse-key   Reuse the existing private key of this FQDN instead of
#                generating a new one. The key must exist.
#  -h, --help    Show this help.
#
# Without options the script asks for the details.
#
# This script automates RSA certificate creation, validation, and
# bundle preparation for services like HAProxy.

# Notes:
# Ensure OpenSSL is installed and configured correctly.
# The script requires valid input for FQDN and IPv4 address.
# Generated certificates will be saved in the user's home directory.
# The script stops on errors and requires successful execution of
# each step to proceed.

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
  echo
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
fqdn=""
ipv4=""
non_interactive=false
reuse_key=false

# Function to parse arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --fqdn)
      [[ -n "$2" && "$2" =~ ^[A-Za-z0-9*][A-Za-z0-9._*-]*$ && "$2" != *..* ]] || {
        echo "[ERROR] --fqdn needs a valid FQDN." >&2
        exit 1
      }
      fqdn="$2"
      non_interactive=true
      shift 2
      ;;
    --ip)
      [[ -n "$2" && "$2" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || {
        echo "[ERROR] --ip needs an IPv4 address." >&2
        exit 1
      }
      ipv4=", IP:$2"
      shift 2
      ;;
    --reuse-key)
      reuse_key=true
      shift
      ;;
    -h | --help)
      sed -n '/^# Usage:/,/^$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      exit 1
      ;;
    esac
  done
}

parse_arguments "$@"

# --ip is only accepted together with --fqdn
if [[ -n "$ipv4" && "$non_interactive" == "false" ]]; then
  echo "[ERROR] --ip can only be used together with --fqdn." >&2
  exit 1
fi

# Ask for the details only when --fqdn is not given
if [ "$non_interactive" = false ]; then
  read -r -p "$(print_cyan "Enter the FQDN name of the new certificate: ")" fqdn
  read -r -p "$(print_cyan "Enter the IPv4 address of the new certificate (syntax: , IP:192.168.x.x): ")" ipv4
fi

# In non-interactive mode the Common Name comes from the FQDN, so openssl req
# does not ask for it again.
req_subject=()
if [ "$non_interactive" = true ]; then
  req_subject=(-subj "/CN=${fqdn}")
fi

# Define directory paths
print_section_header "Define directory paths"
# Set the base directory. The old name ~/ssl is used while ~/tls does not exist.
base_dir="$HOME/tls"
if [ ! -e "$base_dir" ] && [ -d "$HOME/ssl" ]; then
  base_dir="$HOME/ssl"
  echo "Warning: using the old directory $HOME/ssl. Run tls_directory_migrate.sh to move it to $HOME/tls." >&2
fi
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

# Only valid entries (status V, the first field) count. Revoked and updated
# (expired) entries do not block a new certificate, just like in openssl ca.
cn_exists=false
if awk -F'\t' -v cn="/CN=${fqdn}" '
  $1 == "V" && (substr($NF, length($NF) - length(cn) + 1) == cn || index($NF, cn "/")) { found = 1 }
  END { exit !found }' "$db_dir/index.txt" 2>/dev/null; then
  cn_exists=true
fi

# If unique_subject is enabled and Certificate exists, display an error and exit
if [[ "$unique_subject" == "yes" && "$cn_exists" == "true" ]]; then
  echo "[ERROR] unique_subject is enabled and a valid certificate with Common Name ${fqdn} already exists in index.txt." >&2
  echo "Revoke it, or run 'openssl ca -updatedb' if it has expired, and try again." >&2
  exit 1
fi

# Generate RSA key, or reuse the existing key with --reuse-key
if [ "$reuse_key" = true ]; then
  print_section_header "Reuse existing RSA key"
  if [ ! -f "$private_certificates_dir/${fqdn}.pem" ]; then
    echo "[ERROR] No existing key found for ${fqdn} to reuse." >&2
    exit 1
  fi
else
  print_section_header "Generate RSA key"
  openssl genrsa -out "$private_certificates_dir/${fqdn}.pem" 4096
  check_success "Failed to generate RSA key"
fi

# Generate Certificate Signing Request (CSR)
print_section_header "Generate Certificate Signing Request"
openssl req -new -sha256 -config "$openssl_conf_dir/cert.cnf" "${req_subject[@]}" -key "$private_certificates_dir/${fqdn}.pem" -out "$csr_dir/${fqdn}.pem"
check_success "Failed to generate Certificate Signing Request"

# Create an extfile with all the alternative names
print_section_header "Create an extfile with all the alternative names"
{
  echo "subjectAltName = DNS:${fqdn}, DNS:www.${fqdn}${ipv4}"
  echo "basicConstraints = critical, CA:FALSE"
  echo "keyUsage = critical, digitalSignature"
  echo "extendedKeyUsage = serverAuth"
  echo "nsComment = OpenSSL Generated Server Certificate"
} >"$extfile_dir/${fqdn}.cnf"

# Generate Certificate
print_section_header "Generate Certificate"
openssl ca -config "$openssl_conf_dir/cert.cnf" -notext -batch -in "$csr_dir/${fqdn}.pem" -out "$certs_certificates_dir/${fqdn}.pem" -extfile "$extfile_dir/${fqdn}.cnf"
check_success "Failed to generate Certificate"

# Create Certificate Chain Bundle
print_section_header "Create Certificate Chain Bundle"
cat "$certs_certificates_dir/${fqdn}.pem" "$certs_intermediate_dir/ca_chain_bundle.pem" >"$certs_certificates_dir/${fqdn}_chain_bundle.pem"
check_success "Failed to create Certificate Chain Bundle"

# Create Certificate Chain Bundle for HAProxy
print_section_header "Create Certificate Chain Bundle for HAProxy"
cat "$certs_certificates_dir/${fqdn}_chain_bundle.pem" "$private_certificates_dir/${fqdn}.pem" >"$certs_certificates_dir/${fqdn}_haproxy.pem"
chmod 600 "$certs_certificates_dir/${fqdn}_haproxy.pem"
check_success "Failed to create Certificate Chain Bundle for HAProxy"

# Perform certificate verifications
print_section_header "Verify Certificates"
verify_certificate() {
  openssl verify -CAfile "$1" "$2"
  check_success "Verification failed for $2"
}

# Perform certificate verifications
verify_certificate "$certs_certificates_dir/${fqdn}_chain_bundle.pem" "$certs_certificates_dir/${fqdn}.pem"
verify_certificate "$certs_intermediate_dir/ca_chain_bundle.pem" "$certs_certificates_dir/${fqdn}.pem"
verify_certificate "$certs_intermediate_dir/ca_chain_bundle.pem" "$certs_certificates_dir/${fqdn}_chain_bundle.pem"
verify_certificate "$certs_intermediate_dir/ca_chain_bundle.pem" "$certs_certificates_dir/${fqdn}_haproxy.pem"

# Convert Certificate from .pem to .crt and .key
print_section_header "Convert Certificate from .pem to .crt and .key"
cp "$certs_certificates_dir/${fqdn}.pem" "$certs_certificates_dir/${fqdn}.crt"
cp "$certs_certificates_dir/${fqdn}_chain_bundle.pem" "$certs_certificates_dir/${fqdn}_chain_bundle.crt"
cp "$private_certificates_dir/${fqdn}.pem" "$private_certificates_dir/${fqdn}.key"
chmod 600 "$private_certificates_dir/${fqdn}.key"
echo
print_cyan "--> ${fqdn}.crt"
print_cyan "--> ${fqdn}_chain_bundle.crt"
print_cyan "--> ${fqdn}.key"

# Script completion message
echo
print_cyan "Certificate process successfully completed."

exit 0
