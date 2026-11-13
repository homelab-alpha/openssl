#!/bin/bash

# Script Name: cert.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 1.0.0

# Description:
# This script creates a server or client certificate with an ECDSA or RSA key,
# signed by the intermediate certificate authority. The scripts
# cert_ecdsa_server.sh, cert_rsa_server.sh, cert_ecdsa_client.sh,
# cert_rsa_client.sh, and cert_ecdsa_localhost.sh start this script with the
# matching options.
#
# The script generates the private key, the Certificate Signing Request (CSR),
# and the extension file in a temporary folder, issues the certificate, and
# verifies it against the CA chain and the private key. Only then it puts the
# files in place. When a step fails, the existing key and certificate of the
# FQDN are not changed.

# Usage: ./cert.sh --algo <ecdsa|rsa> --role <server|client> [options]
#
# Options:
#  --algo <ecdsa|rsa>     The key type: ECDSA (secp384r1) or RSA (4096 bits).
#  --role <server|client> The kind of certificate.
#  --fqdn <fqdn>          Run without questions for this FQDN. The Common Name
#                         is set to the FQDN.
#  --ip <list>            Server only. Add one or more IPv4 addresses to the
#                         subject alternative names, separated by commas (for
#                         example 192.168.0.1,192.168.0.2). A space after a
#                         comma is allowed. Can be repeated. Only used together
#                         with --fqdn.
#  --www                  Client only. Also add www.<fqdn> to the subject
#                         alternative names. A server certificate always has
#                         this name.
#  --localhost            Create the certificate for localhost (localhost,
#                         *.localhost, and 127.0.0.1). Server only.
#  --non-interactive      Used with --localhost. Set the Common Name to
#                         localhost, so openssl req does not ask for it.
#  --reuse-key            Reuse the existing private key of this FQDN instead
#                         of generating a new one. The key must exist.
#  -h, --help             Show this help.
#
# Without --fqdn the script asks for the details.

# Exit codes:
#  0  Success.
#  1  A step failed. The existing files of the FQDN were not changed.
#  2  Wrong usage or a pre-flight error. Nothing was changed.

# Notes:
# - The certificates are for a homelab and for testing.
# - Certificates are stored under $HOME/tls.
# - A server certificate covers the FQDN and www.<fqdn>. For a wildcard FQDN,
#   such as *.example.test, it covers the wildcard and the domain itself
#   (example.test), because the wildcard already covers www.example.test and
#   does not cover the domain itself.
# - The serial number is random (openssl ca -rand_serial). The script does not
#   change db/serial or db/crlnumber.
# - When the script fails after the certificate was issued, the database keeps
#   an entry for a certificate that is not in use. Revoke it with
#   revoke_tls_certificates.sh.

# Stop script on error
set -Eeuo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

# Function to turn a comma-separated list of IPv4 addresses into subject
# alternative name entries (for example ", IP:192.168.0.1, IP:192.168.0.2").
# Spaces are ignored and duplicates are removed. Returns 1 for invalid input.
build_ip_san() {
  local list="${1// /}" ip octet san="" ips octets
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
    if [[ "$san, " != *", IP:$ip, "* ]]; then
      san+=", IP:$ip"
    fi
  done
  printf '%s' "$san"
}

# Function to remove the temporary folder. It runs from the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    rm -rf "$work_dir"
  fi
}

# Certificate information
algo=""
role=""
fqdn=""
ipv4=""
ip_list=""
add_www=false
localhost=false
non_interactive=false
reuse_key=false
work_dir=""

# Function to parse arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --algo)
      algo="${2:-}"
      shift
      [[ $# -eq 0 ]] || shift
      ;;
    --role)
      role="${2:-}"
      shift
      [[ $# -eq 0 ]] || shift
      ;;
    --fqdn)
      fqdn="${2:-}"
      [[ -n "$fqdn" ]] || {
        print_error "--fqdn needs a valid FQDN."
        exit 2
      }
      non_interactive=true
      shift 2
      ;;
    --ip)
      [[ -n "${2:-}" ]] || {
        print_error "--ip needs one or more IPv4 addresses, separated by commas."
        exit 2
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
    --www)
      add_www=true
      shift
      ;;
    --localhost)
      localhost=true
      shift
      ;;
    --non-interactive)
      non_interactive=true
      shift
      ;;
    --reuse-key)
      reuse_key=true
      shift
      ;;
    -h | --help)
      show_usage '^# Exit codes:'
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      exit 2
      ;;
    esac
  done

  case "$algo" in
  ecdsa | rsa) ;;
  *)
    print_error "--algo needs ecdsa or rsa."
    exit 2
    ;;
  esac
  case "$role" in
  server | client) ;;
  *)
    print_error "--role needs server or client."
    exit 2
    ;;
  esac

  if [[ "$localhost" == "true" ]]; then
    if [[ "$role" != "server" || -n "$fqdn" || -n "$ip_list" ]]; then
      print_error "--localhost is a server certificate and cannot be used with --fqdn or --ip."
      exit 2
    fi
    fqdn="localhost"
    ipv4=", IP:127.0.0.1"
    return
  fi

  if [[ "$non_interactive" == "true" && -z "$fqdn" ]]; then
    print_error "--non-interactive can only be used together with --localhost."
    exit 2
  fi
  if [[ -n "$ip_list" && "$non_interactive" == "false" ]]; then
    print_error "--ip can only be used together with --fqdn."
    exit 2
  fi
  if [[ -n "$ip_list" && "$role" == "client" ]]; then
    print_error "--ip can only be used for a server certificate."
    exit 2
  fi
  if [[ "$add_www" == "true" && "$role" == "server" ]]; then
    print_error "--www is for a client certificate. A server certificate always has www.<fqdn>."
    exit 2
  fi
}

parse_arguments "$@"
require_openssl 2

# Ask for the details only when --fqdn is not given
if [[ "$localhost" == "false" && "$non_interactive" == "false" ]]; then
  read -r -p "$(print_cyan "Enter the FQDN name of the new certificate: ")" fqdn
  if [[ "$role" == "server" ]]; then
    read -r -p "$(print_cyan "Enter the IPv4 addresses of the new certificate, separated by commas (empty for none): ")" ip_list
  fi
fi

# The FQDN becomes a part of file names and of the extension file, so it is
# checked in both modes.
if ! is_valid_fqdn "$fqdn"; then
  print_error "'$fqdn' is not a valid FQDN."
  echo "Use letters, digits, hyphens, and dots, for example server.example.test or *.example.test." >&2
  exit 2
fi
if [[ "$fqdn" == \*.* && "$add_www" == "true" ]]; then
  print_error "--www cannot be used with a wildcard FQDN."
  exit 2
fi

# Validate the IPv4 addresses and build the subject alternative name entries
if [[ -n "${ip_list// /}" ]]; then
  ipv4=$(build_ip_san "$ip_list") || {
    print_error "Invalid IPv4 address list: ${ip_list}"
    echo "Use IPv4 addresses without leading zeros, separated by commas (for example 192.168.0.1,192.168.0.2)." >&2
    exit 2
  }
fi

# In non-interactive mode the Common Name comes from the FQDN, so openssl req
# does not ask for it.
req_subject=()
if [[ "$non_interactive" == "true" ]]; then
  req_subject=(-subj "/CN=${fqdn}")
fi

# Define directory paths
print_section_header "Define directory paths"
set_base_dir
certs_dir="$base_dir/certs"
csr_dir="$base_dir/csr"
extfile_dir="$base_dir/extfiles"
private_dir="$base_dir/private"
db_dir="$base_dir/db"
config_file="$base_dir/openssl.cnf/cert.cnf"
certs_intermediate_dir="$certs_dir/intermediate"
certs_certificates_dir="$certs_dir/certificates"
private_certificates_dir="$private_dir/certificates"
ca_chain="$certs_intermediate_dir/ca_chain_bundle.pem"
key_file="$private_certificates_dir/${fqdn}.pem"

enter_home 2

# Check that everything needed is present, before anything changes
missing=false
for file in "$config_file" "$ca_chain" "$private_dir/intermediate/ca.pem" "$db_dir/index.txt"; do
  if [[ ! -f "$file" ]]; then
    print_error "Required file not found: $file"
    missing=true
  fi
done
for dir in "$certs_certificates_dir" "$private_certificates_dir" "$csr_dir" "$extfile_dir"; do
  if [[ ! -d "$dir" ]]; then
    print_error "Directory not found: $dir"
    missing=true
  fi
done
[[ "$missing" == "false" ]] || exit 2

# Only valid entries (status V, the first field) count. Revoked and updated
# (expired) entries do not block a new certificate, just like in openssl ca.
cn_exists=false
if awk -F'\t' -v cn="/CN=${fqdn}" '
  $1 == "V" && (substr($NF, length($NF) - length(cn) + 1) == cn || index($NF, cn "/")) { found = 1 }
  END { exit !found }' "$db_dir/index.txt"; then
  cn_exists=true
fi

# If unique_subject is enabled and Certificate exists, display an error and exit
if unique_subject_enabled "$db_dir/index.txt.attr" && [[ "$cn_exists" == "true" ]]; then
  print_error "unique_subject is enabled and a valid certificate with Common Name ${fqdn} already exists in index.txt."
  echo "Revoke it, or run 'openssl ca -updatedb' if it has expired, and try again." >&2
  exit 2
fi

if [[ "$reuse_key" == "true" && ! -f "$key_file" ]]; then
  print_error "No existing key found for ${fqdn} to reuse."
  exit 2
fi

# Work in a temporary folder that only the owner can read
work_dir=$(umask 077 && mktemp -d "$base_dir/.cert.XXXXXX")
trap cleanup EXIT
trap 'exit 1' INT TERM
new_key="$work_dir/key.pem"
new_csr="$work_dir/csr.pem"
new_extfile="$work_dir/ext.cnf"
new_cert="$work_dir/cert.pem"
new_chain="$work_dir/chain_bundle.pem"
new_haproxy="$work_dir/haproxy.pem"

# Generate the key, or reuse the existing key with --reuse-key
if [[ "$reuse_key" == "true" ]]; then
  print_section_header "Reuse existing key"
  cp -p "$key_file" "$new_key"
elif [[ "$algo" == "ecdsa" ]]; then
  print_section_header "Generate ECDSA key"
  (umask 077 && openssl ecparam -name secp384r1 -genkey -out "$new_key")
else
  print_section_header "Generate RSA key"
  (umask 077 && openssl genrsa -out "$new_key" 4096)
fi
chmod 600 "$new_key"

# Generate Certificate Signing Request (CSR)
print_section_header "Generate Certificate Signing Request"
digest="sha384"
[[ "$algo" == "ecdsa" ]] || digest="sha256"
openssl req -new "-$digest" -config "$config_file" ${req_subject[@]+"${req_subject[@]}"} -key "$new_key" -out "$new_csr"

# Create an extfile with all the alternative names
print_section_header "Create an extfile with all the alternative names"
if [[ "$localhost" == "true" ]]; then
  san_names="DNS:${fqdn}, DNS:*.${fqdn}"
elif [[ "$fqdn" == \*.* ]]; then
  # A wildcard already covers www.<domain>, and www.*.<domain> is not valid.
  # Add the domain itself instead, because a wildcard does not cover it.
  san_names="DNS:${fqdn}"
  [[ "$role" == "client" ]] || san_names+=", DNS:${fqdn#\*.}"
elif [[ "$role" == "server" || "$add_www" == "true" ]]; then
  san_names="DNS:${fqdn}, DNS:www.${fqdn}"
else
  san_names="DNS:${fqdn}"
fi
if [[ "$role" == "server" ]]; then
  extended_key_usage="serverAuth"
  comment="OpenSSL Generated Server Certificate"
else
  extended_key_usage="clientAuth, emailProtection"
  comment="OpenSSL Generated Client Certificate"
fi
{
  echo "subjectAltName = ${san_names}${ipv4}"
  echo "basicConstraints = critical, CA:FALSE"
  echo "keyUsage = critical, digitalSignature"
  echo "extendedKeyUsage = ${extended_key_usage}"
  echo "nsComment = ${comment}"
} >"$new_extfile"

# Generate Certificate
print_section_header "Generate Certificate"
openssl ca -config "$config_file" -rand_serial -notext -batch -in "$new_csr" -out "$new_cert" -extfile "$new_extfile"

# Create Certificate Chain Bundle
print_section_header "Create Certificate Chain Bundle"
cat "$new_cert" "$ca_chain" >"$new_chain"

# Create Certificate Chain Bundle for HAProxy. It holds the private key.
if [[ "$role" == "server" ]]; then
  print_section_header "Create Certificate Chain Bundle for HAProxy"
  (umask 077 && cat "$new_chain" "$new_key" >"$new_haproxy")
fi

# Verify the certificate against the CA chain and the private key
print_section_header "Verify Certificate"
openssl verify -CAfile "$ca_chain" "$new_cert"
if [[ "$(openssl x509 -in "$new_cert" -noout -pubkey)" != "$(openssl pkey -in "$new_key" -pubout)" ]]; then
  print_error "The new certificate does not match the private key."
  exit 1
fi
echo "The certificate matches the private key."

# Put the files in place. The key goes first, with mode 600.
print_section_header "Install the files"
if [[ "$reuse_key" == "false" ]]; then
  mv -f "$new_key" "$key_file"
fi
cp -pf "$key_file" "$private_certificates_dir/${fqdn}.key"
chmod 600 "$key_file" "$private_certificates_dir/${fqdn}.key"
if [[ "$role" == "server" ]]; then
  mv -f "$new_haproxy" "$certs_certificates_dir/${fqdn}_haproxy.pem"
  chmod 600 "$certs_certificates_dir/${fqdn}_haproxy.pem"
fi
cp -f "$new_csr" "$csr_dir/${fqdn}.pem"
cp -f "$new_extfile" "$extfile_dir/${fqdn}.cnf"
cp -f "$new_cert" "$certs_certificates_dir/${fqdn}.pem"
cp -f "$new_cert" "$certs_certificates_dir/${fqdn}.crt"
cp -f "$new_chain" "$certs_certificates_dir/${fqdn}_chain_bundle.pem"
cp -f "$new_chain" "$certs_certificates_dir/${fqdn}_chain_bundle.crt"
echo
print_cyan "--> ${fqdn}.pem and ${fqdn}.crt"
print_cyan "--> ${fqdn}_chain_bundle.pem and ${fqdn}_chain_bundle.crt"
print_cyan "--> ${fqdn}.key"
if [[ "$role" == "server" ]]; then
  print_cyan "--> ${fqdn}_haproxy.pem"
fi

# Script completion message
echo
print_cyan "Certificate process successfully completed."

exit 0
