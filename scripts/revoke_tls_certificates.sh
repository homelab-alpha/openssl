#!/bin/bash

# Script Name: revoke_tls_certificates.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 1.3.0

# Description:
# This script revokes a server or client certificate and generates a
# Certificate Revocation List (CRL). It marks the valid entry (status V) of the
# FQDN in $HOME/tls/db/index.txt as revoked (status R) with a reason, and then
# creates a new CRL in $HOME/tls/crl/ca_crl.pem, signed by the intermediate CA.
# The script verifies the CRL with the CA chain.
#
# With --authority the script revokes the certificate of an authority, in the
# database of the authority that signed it, and generates the CRL of that
# signer:
#   --authority ca       The intermediate CA. Database $HOME/tls/db/root_ca/,
#                        CRL $HOME/tls/crl/root_crl.pem, signed by the root CA.
#   --authority root_ca  The root CA. Database $HOME/tls/db/trusted_id/, CRL
#                        $HOME/tls/crl/trusted_id_crl.pem, signed by the trusted
#                        identity.
# The trusted identity signs itself and cannot be revoked: remove it from the
# trust stores instead.
#
# The script does not delete any file. The key, the certificate, and the
# bundles of the revoked certificate stay where they are, so stop using them
# yourself. A copy of index.txt is saved before the database is changed.

# Usage: ./revoke_tls_certificates.sh [options] <fqdn>
#        ./revoke_tls_certificates.sh [options] --authority <ca|root_ca>
#        ./revoke_tls_certificates.sh [options] --crl-only [--authority <ca|root_ca>]
#
# Options:
#  <fqdn>             Revoke the valid certificate with this FQDN.
#  --authority <name> Revoke the intermediate CA (ca) or the root CA (root_ca).
#                     With --crl-only: generate the CRL that lists that
#                     authority, without a revocation.
#  --reason <reason>  The reason: unspecified (default), keyCompromise,
#                     affiliationChanged, superseded, or cessationOfOperation.
#                     With --authority also caCompromise.
#  --no-crl           Revoke, but do not generate a new CRL.
#  --crl-only         Only generate a new CRL. Nothing is revoked, and nothing
#                     is asked. Use it to renew the CRL before it expires.
#  --dry-run          Show the plan and exit. Nothing is asked or changed.
#  --yes              Do not ask for confirmation (for scripts).
#  -h, --help         Show this help.
#
# Without --yes, the script shows the plan and asks for confirmation.
# When the key that signs is encrypted, the script asks for its passphrase, or
# reads it from TLS_CA_PASSPHRASE (intermediate CA), TLS_ROOT_CA_PASSPHRASE
# (root CA), or TLS_TRUSTED_ID_PASSPHRASE (trusted identity).

# Exit codes:
#  0  Success.
#  1  A revocation, the CRL, or a check failed.
#  2  Wrong usage or a pre-flight error (for example an unknown FQDN, or a
#     certificate that is not valid). Nothing was changed.

# Notes:
# The certificates are for a homelab and for testing.
# The certificates do not contain a CRL distribution point. Clients do not find
# the CRL by themselves. Install the CRL where it is used, for example in the
# configuration of HAProxy or nginx.
# A CRL of the intermediate CA is valid for 30 days, of the root CA for 90
# days, and of the trusted identity for 365 days (default_crl_days in the
# configuration files). Generate a new CRL with --crl-only before it expires.
# After an authority is revoked, the certificates below it are refused by
# clients that use the CRL. Create the authority again with --replace, and
# then the certificates below it.
# The script changes to $HOME, because configuration files that were copied
# to $HOME/tls/openssl.cnf before version 0.2.0 use HOME = . .
# The renewal script (renew_tls_certificates.sh) marks the old entry of a
# renewed certificate as superseded in the same way, and the authority scripts
# do that with --replace. Run --crl-only afterwards to put those entries in the
# CRL.

# Define directory paths
# Stop script on error. The functions below return a status on purpose, and
# the callers decide what a failure means.
set -Eeuo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh" || exit 2
set_base_dir
certs_dir="$base_dir/certs"
private_dir="$base_dir/private"
crl_dir="$base_dir/crl"
crl_backup_dir="$base_dir/crl-backup"
archive_root="$base_dir/archive"
database_backup_dir="$archive_root/_database"

# The authority that signs: its configuration file, certificate, key, chain,
# and CRL. set_issuer fills these in.
config_file=""
issuer_label=""
issuer_cert=""
issuer_key=""
issuer_chain=""
issuer_passphrase_env=""
crl_file=""
index_file=""
newcerts_dir=""
authority_cert=""
signer_passphrase=""
signer_options=()

# Defaults
target_fqdn=""
authority=""
reason="unspecified"
generate_crl=true
crl_only=false
dry_run=false
assume_yes=false

# State
plan_serials=()
plan_files=()
plan_expires=()
log=""

# Function to show the help text
show_help() {
  sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

# Function to check that a reason is supported
is_valid_reason() {
  case "$1" in
  unspecified | keyCompromise | caCompromise | affiliationChanged | superseded | cessationOfOperation) return 0 ;;
  *) return 1 ;;
  esac
}

# Function to select the authority that signs the certificate to revoke
set_issuer() {
  case "$authority" in
  "")
    config_file="$base_dir/openssl.cnf/cert.cnf"
    issuer_label="intermediate CA"
    issuer_cert="$certs_dir/intermediate/ca.pem"
    issuer_key="$private_dir/intermediate/ca.pem"
    issuer_chain="$certs_dir/intermediate/ca_chain_bundle.pem"
    issuer_passphrase_env="TLS_CA_PASSPHRASE"
    crl_file="$crl_dir/ca_crl.pem"
    ;;
  ca)
    config_file="$base_dir/openssl.cnf/ca.cnf"
    issuer_label="root CA"
    issuer_cert="$certs_dir/root/root_ca.pem"
    issuer_key="$private_dir/root/root_ca.pem"
    issuer_chain="$certs_dir/root/root_ca_chain_bundle.pem"
    issuer_passphrase_env="TLS_ROOT_CA_PASSPHRASE"
    crl_file="$crl_dir/root_crl.pem"
    authority_cert="$certs_dir/intermediate/ca.pem"
    ;;
  root_ca)
    config_file="$base_dir/openssl.cnf/root_ca.cnf"
    issuer_label="trusted identity"
    issuer_cert="$certs_dir/root/trusted_id.pem"
    issuer_key="$private_dir/root/trusted_id.pem"
    issuer_chain="$certs_dir/root/trusted_id.pem"
    issuer_passphrase_env="TLS_TRUSTED_ID_PASSPHRASE"
    crl_file="$crl_dir/trusted_id_crl.pem"
    authority_cert="$certs_dir/root/root_ca.pem"
    ;;
  esac
}

# Function to parse arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --reason)
      is_valid_reason "${2:-}" || {
        print_error "--reason needs one of: unspecified, keyCompromise, caCompromise, affiliationChanged, superseded, cessationOfOperation."
        exit 2
      }
      reason="$2"
      shift 2
      ;;
    --authority)
      case "${2:-}" in
      ca | root_ca) authority="$2" ;;
      *)
        print_error "--authority needs ca (the intermediate CA) or root_ca (the root CA)."
        exit 2
        ;;
      esac
      shift 2
      ;;
    --no-crl)
      generate_crl=false
      shift
      ;;
    --crl-only)
      crl_only=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --yes)
      assume_yes=true
      shift
      ;;
    -h | --help)
      show_help
      exit 0
      ;;
    -*)
      print_error "Unknown option: $1"
      exit 2
      ;;
    *)
      [ -z "$target_fqdn" ] || {
        print_error "Give only one FQDN."
        exit 2
      }
      target_fqdn="$1"
      shift
      ;;
    esac
  done

  if [ "$crl_only" = true ]; then
    [ -z "$target_fqdn" ] || {
      print_error "--crl-only does not take an FQDN."
      exit 2
    }
    [ "$generate_crl" = true ] || {
      print_error "--crl-only and --no-crl cannot be used together."
      exit 2
    }
  elif [ -n "$authority" ]; then
    [ -z "$target_fqdn" ] || {
      print_error "Use either an FQDN or --authority, not both."
      exit 2
    }
  else
    [ -n "$target_fqdn" ] || {
      print_error "Give an FQDN, or use --authority or --crl-only."
      exit 2
    }
  fi
  if [ "$reason" = "caCompromise" ] && [ -z "$authority" ]; then
    print_error "--reason caCompromise can only be used together with --authority."
    exit 2
  fi
  set_issuer
}

# Function to check that everything needed is present, before anything changes
preflight() {
  local missing=false file

  command -v openssl >/dev/null 2>&1 || {
    print_error "OpenSSL is not installed."
    exit 2
  }

  enter_home 2

  [ -f "$config_file" ] || {
    print_error "Required file not found: $config_file"
    exit 2
  }
  # The database of the authority that signs, as named in the configuration file
  index_file=$(config_database "$config_file") || {
    print_error "Cannot read the database path from $config_file."
    exit 2
  }
  newcerts_dir="$base_dir/newcerts"

  for file in \
    "$issuer_cert" \
    "$issuer_chain" \
    "$issuer_key" \
    "$index_file" \
    "$(dirname "$index_file")/crlnumber"; do
    if [ ! -f "$file" ]; then
      print_error "Required file not found: $file"
      missing=true
    fi
  done
  [ -d "$crl_dir" ] || {
    print_error "Directory not found: $crl_dir"
    missing=true
  }
  [ "$missing" = false ] || exit 2

  # The authority that signs must still be usable to sign the CRL
  if ! openssl x509 -in "$issuer_cert" -noout -checkend 0 >/dev/null 2>&1; then
    print_error "The certificate of the $issuer_label has expired or is not readable."
    exit 2
  fi
}

# Function to ask for the passphrase of the key that signs, when it is encrypted
prepare_signer() {
  if key_is_encrypted "$issuer_key"; then
    get_passphrase signer_passphrase "$issuer_passphrase_env" "$issuer_label key" || exit 2
    signer_options=(-passin env:TLS_SIGNER_PASSPHRASE)
  fi
}

# Function to run openssl ca with the key of the authority that signs
signer_ca() {
  TLS_SIGNER_PASSPHRASE="$signer_passphrase" openssl ca -config "$config_file" \
    ${signer_options[@]+"${signer_options[@]}"} "$@" 9>&-
}

# Function to list the serial numbers of the valid (V) entries of an FQDN
list_valid_serials() {
  awk -F'\t' -v cn="/CN=$1" '
    $1 == "V" && (substr($NF, length($NF) - length(cn) + 1) == cn || index($NF, cn "/")) { print $4 }' \
    "$index_file"
}

# Function to check if an FQDN has an entry with status R
has_revoked_entry() {
  awk -F'\t' -v cn="/CN=$1" '
    $1 == "R" && (substr($NF, length($NF) - length(cn) + 1) == cn || index($NF, cn "/")) { found = 1 }
    END { exit !found }' "$index_file"
}

# Function to select the certificate of an authority to revoke
select_authority() {
  local serial enddate
  if [ ! -f "$authority_cert" ]; then
    print_error "Certificate not found: $authority_cert"
    exit 2
  fi
  if ! entry_is_valid "$index_file" "$authority_cert"; then
    print_error "The certificate of '$authority' has no valid entry in $index_file. It is already revoked, or it was issued with another database."
    exit 2
  fi
  serial=$(openssl x509 -in "$authority_cert" -noout -serial 2>/dev/null)
  enddate=$(openssl x509 -in "$authority_cert" -noout -enddate 2>/dev/null)
  plan_serials+=("${serial#serial=}")
  plan_files+=("$authority_cert")
  plan_expires+=("${enddate#notAfter=}")
}

# Function to select the entries to revoke
select_targets() {
  local serial cert enddate

  if [ -n "$authority" ]; then
    select_authority
    return
  fi

  case "$target_fqdn" in
  trusted_id | root_ca | ca)
    print_error "'$target_fqdn' is a CA certificate. Use --authority ca or --authority root_ca to revoke an authority."
    exit 2
    ;;
  esac
  is_valid_fqdn "$target_fqdn" || {
    print_error "'$target_fqdn' is not a valid FQDN."
    exit 2
  }

  while IFS= read -r serial; do
    [ -n "$serial" ] || continue
    cert="$newcerts_dir/$serial.pem"
    if [ ! -f "$cert" ]; then
      print_error "The certificate file of serial $serial is missing: $cert"
      exit 2
    fi
    enddate=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null)
    plan_serials+=("$serial")
    plan_files+=("$cert")
    plan_expires+=("${enddate#notAfter=}")
  done < <(list_valid_serials "$target_fqdn")

  if [ "${#plan_serials[@]}" -eq 0 ]; then
    if has_revoked_entry "$target_fqdn"; then
      print_error "No valid certificate found for $target_fqdn. It is already revoked."
    else
      print_error "No valid certificate found for $target_fqdn in $index_file."
    fi
    exit 2
  fi
}

# Function to print the plan
print_plan() {
  local i
  print_cyan "=== Revocation plan ==="
  printf '%-40s %-42s %-26s %s\n' "NAME" "SERIAL" "EXPIRES" "REASON"
  for i in "${!plan_serials[@]}"; do
    printf '%-40s %-42s %-26s %s\n' "$target_name" "${plan_serials[$i]}" "${plan_expires[$i]}" "$reason"
  done
  echo
  echo "The database entry in $index_file is marked as revoked. No file is deleted."
  if [ -n "$authority" ]; then
    print_warning "Clients that use the CRL then refuse every certificate below this authority."
  fi
  if [ "$generate_crl" = true ]; then
    echo "A new CRL is generated in $crl_file."
  fi
}

# Function to save a copy of the database before it changes
backup_database() {
  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  (umask 077 && mkdir -p "$database_backup_dir") || return 1
  (umask 077 && cp -p "$index_file" "$database_backup_dir/$backup_name.$stamp") || return 1
  log="$database_backup_dir/revoke.$stamp.log"
  echo "Database copy: $database_backup_dir/$backup_name.$stamp"
}

# Function to revoke the planned entries
revoke_entries() {
  local i status=0
  for i in "${!plan_serials[@]}"; do
    if signer_ca -revoke "${plan_files[$i]}" -crl_reason "$reason" >>"$log" 2>&1; then
      echo "Revoked: ${plan_serials[$i]} ($reason)"
    else
      print_error "Cannot revoke serial ${plan_serials[$i]}. Last lines of $log:"
      tail -n 10 "$log" >&2
      status=1
    fi
  done

  # No valid entry may be left
  if [ "$status" -eq 0 ]; then
    if [ -n "$authority" ]; then
      if entry_is_valid "$index_file" "$authority_cert"; then
        print_error "The certificate of '$authority' still has a valid entry in $index_file."
        status=1
      fi
    elif [ -n "$(list_valid_serials "$target_fqdn")" ]; then
      print_error "$target_fqdn still has a valid entry in $index_file."
      status=1
    fi
  fi
  return $status
}

# Function to generate and check the CRL
create_crl() {
  local stamp count
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  if [ -z "$log" ]; then
    (umask 077 && mkdir -p "$database_backup_dir") || return 1
    log="$database_backup_dir/crl.$stamp.log"
  fi

  # Keep the previous CRL
  if [ -f "$crl_file" ]; then
    (umask 077 && mkdir -p "$crl_backup_dir" && cp -p "$crl_file" "$crl_backup_dir/$(basename "$crl_file" .pem).$stamp.pem") || {
      print_error "Cannot save the previous CRL. The CRL was not changed."
      return 1
    }
  fi

  signer_ca -gencrl -out "$crl_file.new" >>"$log" 2>&1 || {
    print_error "Cannot generate the CRL."
    rm -f "$crl_file.new"
    return 1
  }
  if ! openssl crl -in "$crl_file.new" -noout -CAfile "$issuer_chain" >>"$log" 2>&1; then
    print_error "The new CRL does not verify against the CA chain."
    rm -f "$crl_file.new"
    return 1
  fi
  mv "$crl_file.new" "$crl_file" || return 1
  chmod 644 "$crl_file"

  count=$(openssl crl -in "$crl_file" -noout -text | grep -c "Serial Number:")
  echo "CRL: $crl_file"
  echo "Revoked certificates in the CRL: $count"
  openssl crl -in "$crl_file" -noout -lastupdate -nextupdate
  print_warning "The certificates have no CRL distribution point. Install the CRL where it is used. Generate a new one with --crl-only before it expires."
}

# Main process
parse_arguments "$@"
preflight
# Prevent a revocation during a renewal. The lock is taken before the plan is
# made, so the plan matches the database. The commands that this script starts
# do not inherit the lock (9>&-).
[ "$dry_run" = true ] || acquire_lock 2 0 "A renewal, a revocation, or a certificate script is running."

target_name="${target_fqdn:-$authority}"
backup_name="index.txt"
[ -z "$authority" ] || backup_name="index.txt.$(basename "$(dirname "$index_file")")"

if [ "$crl_only" = false ]; then
  select_targets
  print_plan
  if [ "$dry_run" = true ]; then
    exit 0
  fi
  if [ "$assume_yes" = false ] && ! confirm; then
    echo "Cancelled. Nothing was changed."
    exit 0
  fi
elif [ "$dry_run" = true ]; then
  echo "A new CRL would be generated in $crl_file."
  exit 0
fi

prepare_signer
status=0

if [ "$crl_only" = false ]; then
  backup_database || {
    print_error "Cannot save a copy of index.txt. Nothing was changed."
    exit 1
  }
  revoke_entries || status=1
fi

# Generate the CRL, also after a partial failure, so it matches the database
if [ "$generate_crl" = true ]; then
  create_crl || status=1
fi

if [ "$status" -ne 0 ]; then
  exit 1
fi

if [ "$crl_only" = false ]; then
  echo
  print_cyan "Revoked $target_name. The files of the certificate are still in place; stop using them."
  if [ -n "$authority" ]; then
    echo "Create the authority again with --replace, and then the certificates below it."
  fi
fi
exit 0
