#!/bin/bash

# Script Name: revoke_tls_certificates.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-09T10:00:00+01:00
# Version: 1.1.0

# Description:
# This script revokes a server or client certificate and generates a
# Certificate Revocation List (CRL). It marks the valid entry (status V) of the
# FQDN in $HOME/tls/db/index.txt as revoked (status R) with a reason, and then
# creates a new CRL in $HOME/tls/crl/ca_crl.pem, signed by the intermediate CA.
# The script verifies the CRL with the CA chain.
#
# The script does not delete any file. The key, the certificate, and the
# bundles of the revoked certificate stay where they are, so stop using them
# yourself. A copy of index.txt is saved before the database is changed.
#
# CA certificates (trusted identity, root, and intermediate) are not revoked.

# Usage: ./revoke_tls_certificates.sh [options] <fqdn>
#        ./revoke_tls_certificates.sh [options] --crl-only
#
# Options:
#  <fqdn>             Revoke the valid certificate with this FQDN.
#  --reason <reason>  The reason: unspecified (default), keyCompromise,
#                     affiliationChanged, superseded, or cessationOfOperation.
#  --no-crl           Revoke, but do not generate a new CRL.
#  --crl-only         Only generate a new CRL. Nothing is revoked, and nothing
#                     is asked. Use it to renew the CRL before it expires.
#  --dry-run          Show the plan and exit. Nothing is asked or changed.
#  --yes              Do not ask for confirmation (for scripts).
#  -h, --help         Show this help.
#
# Without --yes, the script shows the plan and asks for confirmation.

# Exit codes:
#  0  Success.
#  1  A revocation, the CRL, or a check failed.
#  2  Wrong usage or a pre-flight error (for example an unknown FQDN, or a
#     certificate that is not valid). Nothing was changed.

# Notes:
# The certificates are for a homelab and for testing.
# The certificates do not contain a CRL distribution point. Clients do not find
# the CRL by themselves. Install ca_crl.pem where it is used, for example in
# the configuration of HAProxy or nginx.
# A CRL is valid for 30 days (default_crl_days in cert.cnf). Generate a new CRL
# with --crl-only before it expires.
# The script must run with $HOME as the current directory, because the
# OpenSSL configuration files use HOME = . . The script changes to it itself.
# The renewal script (renew_tls_certificates.sh) marks the old entry of a
# renewed certificate as superseded in the same way. Run --crl-only afterwards
# to put those entries in the CRL.

# Define directory paths
# Set the base directory. The old name ~/ssl is used while ~/tls does not exist.
base_dir="$HOME/tls"
if [ ! -e "$base_dir" ] && [ -d "$HOME/ssl" ]; then
  base_dir="$HOME/ssl"
  echo "Warning: using the old directory $HOME/ssl. Run tls_directory_migrate.sh to move it to $HOME/tls." >&2
fi
certs_dir="$base_dir/certs"
private_dir="$base_dir/private"
db_dir="$base_dir/db"
certs_intermediate_dir="$certs_dir/intermediate"
crl_dir="$base_dir/crl"
crl_backup_dir="$base_dir/crl-backup"
newcerts_dir="$base_dir/newcerts"
archive_root="$base_dir/archive"
database_backup_dir="$archive_root/_database"
lock_file="$base_dir/.renew.lock"
config_file="$base_dir/openssl.cnf/cert.cnf"
crl_file="$crl_dir/ca_crl.pem"

# Defaults
target_fqdn=""
reason="unspecified"
generate_crl=true
crl_only=false
dry_run=false
assume_yes=false

# State
plan_serials=()
plan_expires=()
log=""

# Function to print text in cyan color
print_cyan() {
  echo -e "\e[36m$1\e[0m"
}

# Function to print an error message
print_error() {
  echo "[ERROR] $1" >&2
}

# Function to print a warning message
print_warning() {
  echo -e "\e[33m[WARNING] $1\e[0m" >&2
}

# Function to show the help text
show_help() {
  sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

# Function to check that a value is a usable FQDN
is_valid_fqdn() {
  [[ -n "$1" && "$1" =~ ^[A-Za-z0-9*][A-Za-z0-9._*-]*$ && "$1" != *..* ]]
}

# Function to check that a reason is supported
is_valid_reason() {
  case "$1" in
  unspecified | keyCompromise | affiliationChanged | superseded | cessationOfOperation) return 0 ;;
  *) return 1 ;;
  esac
}

# Function to parse arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --reason)
      is_valid_reason "$2" || {
        print_error "--reason needs one of: unspecified, keyCompromise, affiliationChanged, superseded, cessationOfOperation."
        exit 2
      }
      reason="$2"
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
  else
    [ -n "$target_fqdn" ] || {
      print_error "Give an FQDN, or use --crl-only."
      exit 2
    }
  fi
}

# Function to check that everything needed is present, before anything changes
preflight() {
  local missing=false file

  command -v openssl >/dev/null 2>&1 || {
    print_error "OpenSSL is not installed."
    exit 2
  }

  cd "$HOME" || {
    print_error "Cannot change to $HOME."
    exit 2
  }

  for file in \
    "$certs_intermediate_dir/ca.pem" \
    "$certs_intermediate_dir/ca_chain_bundle.pem" \
    "$private_dir/intermediate/ca.pem" \
    "$db_dir/index.txt" \
    "$db_dir/crlnumber" \
    "$config_file"; do
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

  # The intermediate CA must still be usable to sign the CRL
  if ! openssl x509 -in "$certs_intermediate_dir/ca.pem" -noout -checkend 0 >/dev/null 2>&1; then
    print_error "The intermediate CA certificate has expired or is not readable."
    exit 2
  fi
}

# Function to list the serial numbers of the valid (V) entries of an FQDN
list_valid_serials() {
  awk -F'\t' -v cn="/CN=$1" '
    $1 == "V" && (substr($NF, length($NF) - length(cn) + 1) == cn || index($NF, cn "/")) { print $4 }' \
    "$db_dir/index.txt"
}

# Function to check if an FQDN has an entry with status R
has_revoked_entry() {
  awk -F'\t' -v cn="/CN=$1" '
    $1 == "R" && (substr($NF, length($NF) - length(cn) + 1) == cn || index($NF, cn "/")) { found = 1 }
    END { exit !found }' "$db_dir/index.txt"
}

# Function to select the entries to revoke
select_targets() {
  local serial cert enddate

  case "$target_fqdn" in
  trusted_id | root_ca | ca)
    print_error "'$target_fqdn' is a CA certificate. This script does not revoke CA certificates."
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
    plan_expires+=("${enddate#notAfter=}")
  done < <(list_valid_serials "$target_fqdn")

  if [ "${#plan_serials[@]}" -eq 0 ]; then
    if has_revoked_entry "$target_fqdn"; then
      print_error "No valid certificate found for $target_fqdn. It is already revoked."
    else
      print_error "No valid certificate found for $target_fqdn in $db_dir/index.txt."
    fi
    exit 2
  fi
}

# Function to print the plan
print_plan() {
  local i
  print_cyan "=== Revocation plan ==="
  printf '%-40s %-34s %-26s %s\n' "FQDN" "SERIAL" "EXPIRES" "REASON"
  for i in "${!plan_serials[@]}"; do
    printf '%-40s %-34s %-26s %s\n' "$target_fqdn" "${plan_serials[$i]}" "${plan_expires[$i]}" "$reason"
  done
  echo
  echo "The database entry is marked as revoked. No file is deleted."
  if [ "$generate_crl" = true ]; then
    echo "A new CRL is generated in $crl_file."
  fi
}

# Function to ask for confirmation
confirm() {
  local answer
  read -r -p "Do you want to continue? (yes/no): " answer
  [[ "$answer" == "yes" ]]
}

# Function to save a copy of the database before it changes
backup_database() {
  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  (umask 077 && mkdir -p "$database_backup_dir") || return 1
  (umask 077 && cp -p "$db_dir/index.txt" "$database_backup_dir/index.txt.$stamp") || return 1
  log="$database_backup_dir/revoke.$stamp.log"
  echo "Database copy: $database_backup_dir/index.txt.$stamp"
}

# Function to revoke the planned entries
revoke_entries() {
  local serial status=0
  for serial in "${plan_serials[@]}"; do
    if openssl ca -config "$config_file" -revoke "$newcerts_dir/$serial.pem" -crl_reason "$reason" >>"$log" 2>&1 9>&-; then
      echo "Revoked: $serial ($reason)"
    else
      print_error "Cannot revoke serial $serial. Last lines of $log:"
      tail -n 10 "$log" >&2
      status=1
    fi
  done

  # No valid entry may be left for this FQDN
  if [ "$status" -eq 0 ] && [ -n "$(list_valid_serials "$target_fqdn")" ]; then
    print_error "$target_fqdn still has a valid entry in $db_dir/index.txt."
    status=1
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
    (umask 077 && mkdir -p "$crl_backup_dir" && cp -p "$crl_file" "$crl_backup_dir/ca_crl.$stamp.pem") || {
      print_error "Cannot save the previous CRL. The CRL was not changed."
      return 1
    }
  fi

  openssl ca -config "$config_file" -gencrl -out "$crl_file.new" >>"$log" 2>&1 9>&- || {
    print_error "Cannot generate the CRL."
    rm -f "$crl_file.new"
    return 1
  }
  if ! openssl crl -in "$crl_file.new" -noout -CAfile "$certs_intermediate_dir/ca_chain_bundle.pem" >>"$log" 2>&1; then
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

# Prevent a revocation during a renewal. The commands that this script starts
# do not inherit the lock (9>&-).
if command -v flock >/dev/null 2>&1; then
  exec 9>"$lock_file"
  flock -n 9 || {
    print_error "A renewal or revocation is running."
    exit 2
  }
else
  print_warning "flock is not installed, so overlapping runs are not prevented."
fi

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
  print_cyan "Revoked $target_fqdn. The files of the certificate are still in place; stop using them."
fi
exit 0
