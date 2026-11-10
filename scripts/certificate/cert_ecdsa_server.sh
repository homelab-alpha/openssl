#!/bin/bash

# Script Name: cert_ecdsa_server.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-09T10:00:00+01:00
# Version: 2.7.3

# Description:
# This script automates the creation of an ECDSA server certificate. It
# generates the private key, creates a Certificate Signing Request (CSR),
# and issues the final certificate. The script also creates an extension
# file for certificate attributes, bundles the certificate with an
# intermediate CA chain, and performs several verification steps. It also
# prepares a certificate bundle for use with HAProxy and converts the
# certificate into multiple formats for various applications.

# Usage: ./cert_ecdsa_server.sh [--fqdn <fqdn> [--ip <ipv4>[,<ipv4>...]]] [--reuse-key] [-h|--help]
#
# Options:
#  --fqdn <fqdn> Run without questions for this FQDN. The Common Name is
#                set to the FQDN, so it is not asked a second time.
#  --ip <list>   Add one or more IPv4 addresses to the subject alternative
#                names, separated by commas (for example
#                192.168.0.1,192.168.0.2). A space after a comma is
#                allowed (192.168.0.1, 192.168.0.2). Can be repeated. Only
#                used together with --fqdn.
#  --reuse-key   Reuse the existing private key of this FQDN instead of
#                generating a new one. The key must exist.
#  -h, --help    Show this help.
#
# Without options the script asks for the details.

# Notes:
# - Requires OpenSSL to be installed on the system.
# - Certificates will be stored in directories under the HOME/tls folder.
# - The script will prompt for the Fully Qualified Domain Name (FQDN) and
#   the IPv4 addresses of the certificate.
# - A certificate covers the FQDN and www.<fqdn>. For a wildcard FQDN, such as
#   *.example.test, it covers the wildcard and the domain itself (example.test),
#   because the wildcard already covers www.example.test and does not cover the
#   domain itself.

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

# Function to turn a comma-separated list of IPv4 addresses into subject
# alternative name entries (for example ", IP:192.168.0.1, IP:192.168.0.2").
# Spaces are ignored and duplicates are removed. Returns 1 for invalid input.
build_ip_san() {
  local list="${1// /}" ip octet san="" ips octets
  local -A seen=()
  if [[ -z "$list" || "$list" == ,* || "$list" == *, || "$list" == *,,* ]]; then
    return 1
  fi
  IFS=',' read -r -a ips <<<"$list"
  for ip in "${ips[@]}"; do
    # Four decimal octets without leading zeros, each between 0 and 255
    [[ "$ip" =~ ^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$ ]] || return 1
    IFS='.' read -r -a octets <<<"$ip"
    for octet in "${octets[@]}"; do
      ((octet <= 255)) || return 1
    done
    if [[ -z "${seen[$ip]:-}" ]]; then
      seen[$ip]=1
      san+=", IP:$ip"
    fi
  done
  printf '%s' "$san"
}

# Certificate information
fqdn=""
ipv4=""
ip_list=""
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
      [[ -n "${2:-}" ]] || {
        echo "[ERROR] --ip needs one or more IPv4 addresses, separated by commas." >&2
        exit 1
      }
      ip_list+="${ip_list:+,}$2"
      shift 2
      # Without quotes, the shell splits "a, b" into separate arguments. Take the
      # next argument as well when the list so far ends with a comma, or when the
      # next argument starts with a comma.
      while [[ $# -gt 0 && "$1" != -* ]] && [[ "$ip_list" == *, || "$1" == ,* ]]; do
        ip_list+="$1"
        shift
      done
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
if [[ -n "$ip_list" && "$non_interactive" == "false" ]]; then
  echo "[ERROR] --ip can only be used together with --fqdn." >&2
  exit 1
fi

# Ask for the details only when --fqdn is not given
if [ "$non_interactive" = false ]; then
  read -r -p "$(print_cyan "Enter the FQDN name of the new certificate: ")" fqdn
  read -r -p "$(print_cyan "Enter the IPv4 addresses of the new certificate, separated by commas (empty for none): ")" ip_list
fi

# Validate the IPv4 addresses and build the subject alternative name entries
if [[ -n "${ip_list// /}" ]]; then
  ipv4=$(build_ip_san "$ip_list") || {
    echo "[ERROR] Invalid IPv4 address list: ${ip_list}" >&2
    echo "Use IPv4 addresses without leading zeros, separated by commas (for example 192.168.0.1,192.168.0.2)." >&2
    exit 1
  }
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

# Generate ECDSA key, or reuse the existing key with --reuse-key
if [ "$reuse_key" = true ]; then
  print_section_header "Reuse existing ECDSA key"
  if [ ! -f "$private_certificates_dir/${fqdn}.pem" ]; then
    echo "[ERROR] No existing key found for ${fqdn} to reuse." >&2
    exit 1
  fi
else
  print_section_header "Generate ECDSA key"
  openssl ecparam -name secp384r1 -genkey -out "$private_certificates_dir/${fqdn}.pem"
  check_success "Failed to generate ECDSA key"
fi

# Generate Certificate Signing Request (CSR)
print_section_header "Generate Certificate Signing Request"
openssl req -new -sha384 -config "$openssl_conf_dir/cert.cnf" "${req_subject[@]}" -key "$private_certificates_dir/${fqdn}.pem" -out "$csr_dir/${fqdn}.pem"
check_success "Failed to generate Certificate Signing Request"

# Create an extfile with all the alternative names
print_section_header "Create an extfile with all the alternative names"
if [[ "$fqdn" == \*.* ]]; then
  # A wildcard already covers www.<domain>, and www.*.<domain> is not valid.
  # Add the domain itself instead, because a wildcard does not cover it.
  san_names="DNS:${fqdn}, DNS:${fqdn#\*.}"
else
  san_names="DNS:${fqdn}, DNS:www.${fqdn}"
fi
{
  echo "subjectAltName = ${san_names}${ipv4}"
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
