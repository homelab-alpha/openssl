#!/bin/bash

# Script Name: renew_tls_certificates.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 1.4.0

# Description:
# This script renews server and client certificates before they expire. It
# detects the kind of each certificate (RSA or ECDSA, server or client) from
# the existing files and calls the matching certificate script in
# scripts/certificate/ without questions. It does not contain its own issuance
# logic.
#
# For every renewal the script:
# - Archives the old key, certificate, and bundles in a dated folder under
#   $HOME/tls/archive/<fqdn>/ before anything is overwritten. Nothing is ever
#   deleted.
# - Issues the new certificate with the same names (subject alternative names).
#   A new key is generated, unless --reuse-key is given.
# - Rebuilds the chain bundle and the HAProxy bundle (mode 600) and verifies
#   the chain, the key, and the names.
# - Restores the archived files when a step fails, so the old certificate
#   keeps working.
# - Runs the executable files in $HOME/tls/hooks.d/ after a successful renewal.
#
# CA certificates (trusted identity, root, and intermediate) are never renewed.
# The script prints a warning when a CA certificate expires soon.
# A certificate that is revoked in $HOME/tls/db/index.txt (status R) is never
# renewed. With --all it is skipped. Issue a new certificate for it with the
# certificate scripts instead.

# Usage: ./renew_tls_certificates.sh [options] <fqdn>
#        ./renew_tls_certificates.sh [options] --all --within <days>
#
# Options:
#  <fqdn>             Renew the certificate with this FQDN.
#  --all              Renew all server and client certificates that expire
#                     within the number of days given with --within.
#  --within <days>    Used with --all. Includes certificates that have
#                     expired already.
#  --reuse-key        Reuse the existing private key instead of a new key.
#  --dry-run          Show the plan and exit. Nothing is asked or changed.
#  --yes              Do not ask for confirmation (for cron and timers).
#  -h, --help         Show this help.
#
# Without --yes, the script shows the plan and asks for confirmation.

# Exit codes:
#  0  Success, or nothing to renew.
#  1  A renewal, a check, or a hook failed.
#  2  Wrong usage or a pre-flight error (for example an unknown FQDN or a
#     missing intermediate CA). Nothing was changed.

# Hooks:
# Every executable file in $HOME/tls/hooks.d/ runs after a successful renewal,
# in alphabetical order, with these arguments:
#   <fqdn> <certificate> <chain_bundle> <key> <haproxy_bundle>
# The HAProxy bundle is an empty string for client certificates. A failing hook
# makes the script exit with code 1, but it does not undo the renewal. A file
# that is not executable is skipped. See examples/hooks.d/ for an example.

# Notes:
# The certificates are for a homelab and for testing.
# The key of the intermediate CA is not encrypted by default. A renewal that
# runs unattended can therefore read it. Protect $HOME/tls/private. When the
# key is encrypted (ca.sh --passphrase), set TLS_CA_PASSPHRASE.
# The names of a certificate (subject alternative names) are read from the
# existing certificate. Only the names that the certificate scripts create
# (FQDN, www.FQDN, and IPv4 addresses) are supported. For a wildcard FQDN the
# domain itself replaces www.FQDN. A certificate with other names is refused,
# because the certificate scripts cannot reproduce it.
# openssl ca refuses a second valid certificate with the same name while
# unique_subject is "yes", and it cannot load a database that holds two valid
# entries with the same name. Therefore the script sets unique_subject to "no"
# in $HOME/tls/db/index.txt.attr during a renewal, marks the old entry in
# index.txt as revoked with the reason "superseded", and then restores
# unique_subject. This is a database marking only: the script does not create a
# CRL. Run revoke_tls_certificates.sh --crl-only afterwards to put the entry in
# the CRL. The old certificate stays in the archive. When a renewal fails after
# the new certificate was issued, the new entry is marked in the same way and
# the old files are restored. If the script cannot repair the database, it
# leaves unique_subject at "no" and prints a warning.
# The script changes to $HOME, because configuration files that were copied
# to $HOME/tls/openssl.cnf before version 0.2.0 use HOME = . .

# Stop script on error. The functions below return a status on purpose, and
# the callers decide what a failure means.
set -Eeuo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh" || exit 2

# Define directory paths
set_base_dir
certs_dir="$base_dir/certs"
private_dir="$base_dir/private"
db_dir="$base_dir/db"
certs_root_dir="$certs_dir/root"
certs_intermediate_dir="$certs_dir/intermediate"
certs_certificates_dir="$certs_dir/certificates"
private_certificates_dir="$private_dir/certificates"
hooks_dir="$base_dir/hooks.d"
archive_root="$base_dir/archive"
attr_file="$db_dir/index.txt.attr"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
certificate_script_dir="$script_dir/certificate"

# Defaults
target_fqdn=""
renew_all=false
within_days=""
reuse_key=false
dry_run=false
assume_yes=false
ca_warn_days=180

# State
plan_fqdn=()
plan_algo=()
plan_kind=()
plan_ip=()
plan_www=()
plan_expires=()
plan_failed=0
attr_changed=false
attr_created=false
attr_original=""
renewed=0
failed=0
renewal_in_progress=""
renewal_old_serial=""
ca_options=()

# Function to show the help text
show_help() {
  sed -n '/^# Usage:/,/^# Hooks:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

# Function to check that a value is a positive integer
is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# Function to parse arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --all)
      renew_all=true
      shift
      ;;
    --within)
      is_number "${2:-}" || {
        print_error "--within needs a number of days."
        exit 2
      }
      within_days="$2"
      shift 2
      ;;
    --reuse-key)
      reuse_key=true
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
      [[ -z "$target_fqdn" ]] || {
        print_error "Give only one FQDN, or use --all --within <days>."
        exit 2
      }
      target_fqdn="$1"
      shift
      ;;
    esac
  done

  if [[ "$renew_all" = true ]]; then
    [[ -z "$target_fqdn" ]] || {
      print_error "Use either an FQDN or --all, not both."
      exit 2
    }
    [[ -n "$within_days" ]] || {
      print_error "--all needs --within <days>."
      exit 2
    }
  else
    [[ -z "$within_days" ]] || {
      print_error "--within can only be used together with --all."
      exit 2
    }
    [[ -n "$target_fqdn" ]] || {
      print_error "Give an FQDN, or use --all --within <days>."
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

  enter_home 2

  for file in \
    "$certs_intermediate_dir/ca.pem" \
    "$certs_intermediate_dir/ca_chain_bundle.pem" \
    "$private_dir/intermediate/ca.pem" \
    "$db_dir/index.txt" \
    "$db_dir/serial" \
    "$base_dir/openssl.cnf/cert.cnf"; do
    if [[ ! -f "$file" ]]; then
      print_error "Required file not found: $file"
      missing=true
    fi
  done
  [[ -d "$certs_certificates_dir" ]] || {
    print_error "Directory not found: $certs_certificates_dir"
    missing=true
  }
  for file in cert cert_rsa_server cert_ecdsa_server cert_rsa_client cert_ecdsa_client cert_ecdsa_localhost; do
    if [[ ! -f "$certificate_script_dir/$file.sh" ]]; then
      print_error "Certificate script not found: $certificate_script_dir/$file.sh"
      missing=true
    fi
  done
  [[ "$missing" = false ]] || exit 2

  # An encrypted key of the intermediate CA needs its passphrase in the
  # environment: the certificate scripts run without a terminal.
  if key_is_encrypted "$private_dir/intermediate/ca.pem"; then
    if [[ -z "${TLS_CA_PASSPHRASE:-}" ]]; then
      print_error "The key of the intermediate CA is encrypted. Set TLS_CA_PASSPHRASE to renew."
      exit 2
    fi
    export TLS_CA_PASSPHRASE
    ca_options=(-passin env:TLS_CA_PASSPHRASE)
  fi

  # The intermediate CA must still be usable
  if ! openssl x509 -in "$certs_intermediate_dir/ca.pem" -noout -checkend 0 >/dev/null 2>&1; then
    print_error "The intermediate CA certificate has expired or is not readable. Renew the CA first."
    exit 2
  fi
}

# Function to warn about CA certificates that expire soon
warn_ca_certificates() {
  local days="$ca_warn_days" file name
  [[ -z "$within_days" ]] || [[ "$within_days" -le "$days" ]] || days="$within_days"
  for file in "$certs_root_dir"/trusted_id.pem "$certs_root_dir"/root_ca.pem "$certs_intermediate_dir"/ca.pem; do
    [[ -f "$file" ]] || continue
    name=$(basename "$file" .pem)
    if ! openssl x509 -in "$file" -noout -checkend "$((days * 86400))" >/dev/null 2>&1; then
      print_warning "CA certificate '$name' expires within $days days. This script does not renew CA certificates."
    fi
  done
}

# Function to get the normalized subject alternative names of a certificate
get_san() {
  # A certificate without names gives an empty list, not an error
  openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null | tail -n +2 | tr -d ' ' | tr ',' '\n' | sort || true
}

# Function to check if a certificate is revoked in the database (status R)
is_revoked() {
  local serial
  serial=$(openssl x509 -in "$1" -noout -serial 2>/dev/null)
  serial="${serial#serial=}"
  awk -F'\t' -v s="$serial" '
    function norm(x) { x = toupper(x); sub(/^0+/, "", x); return x }
    $1 == "R" && norm($4) == norm(s) { found = 1 }
    END { exit !found }' "$db_dir/index.txt"
}

# Function to detect the kind of a certificate and add it to the plan
plan_certificate() {
  local fqdn="$1" cert="$certs_certificates_dir/$1.pem" text algo kind enddate token ips=() ip="" wildcard_domain="" www=false

  if [[ ! -f "$cert" ]]; then
    print_error "No certificate found for $fqdn in $certs_certificates_dir."
    return 1
  fi
  text=$(openssl x509 -in "$cert" -noout -text 2>/dev/null) || {
    print_error "Cannot read the certificate of $fqdn."
    return 1
  }
  if is_revoked "$cert"; then
    print_error "$fqdn is revoked. Issue a new certificate with the certificate scripts."
    return 1
  fi

  # RSA or ECDSA, from the public key algorithm
  case "$text" in
  *"Public Key Algorithm: rsaEncryption"*) algo="rsa" ;;
  *"Public Key Algorithm: id-ecPublicKey"*) algo="ecdsa" ;;
  *)
    print_error "Unsupported public key algorithm for $fqdn."
    return 1
    ;;
  esac

  # Server or client, from the extended key usage
  if [[ "$text" == *"TLS Web Server Authentication"* ]]; then
    kind="server"
  elif [[ "$text" == *"TLS Web Client Authentication"* ]]; then
    kind="client"
  else
    print_error "$fqdn is not a server or client certificate (extended key usage)."
    return 1
  fi

  if [[ "$reuse_key" = true ]] && [[ ! -f "$private_certificates_dir/$fqdn.pem" ]]; then
    print_error "--reuse-key: no private key found for $fqdn."
    return 1
  fi

  # The names must be the ones that the certificate scripts create
  if [[ "$fqdn" = "localhost" ]]; then
    if [[ "$algo" != "ecdsa" ]] || [[ "$kind" != "server" ]]; then
      print_error "localhost can only be renewed as an ECDSA server certificate."
      return 1
    fi
  else
    # A wildcard certificate also holds the domain itself (*.example.test and example.test)
    if [[ "$fqdn" == \*.* ]]; then
      wildcard_domain="${fqdn#\*.}"
    fi
    while IFS= read -r token; do
      case "$token" in
      "DNS:$fqdn") ;;
      "DNS:www.$fqdn") www=true ;;
      "DNS:${wildcard_domain:-$fqdn}") ;;
      IPAddress:*) ips+=("${token#IPAddress:}") ;;
      *)
        print_error "$fqdn has other names than the certificate scripts create ($token). Renew it by hand."
        return 1
        ;;
      esac
    done < <(get_san "$cert")
    if [[ "${#ips[@]}" -gt 0 ]]; then
      # Only the server scripts add IPv4 addresses, and only IPv4 is supported
      if [[ "$kind" = "client" ]]; then
        print_error "$fqdn has IP addresses that the certificate scripts cannot reproduce. Renew it by hand."
        return 1
      fi
      for token in "${ips[@]}"; do
        if ! [[ "$token" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
          print_error "$fqdn has an IP address that is not IPv4 ($token). Renew it by hand."
          return 1
        fi
      done
      ip=$(
        IFS=,
        echo "${ips[*]}"
      )
    fi
  fi

  enddate=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null)
  plan_fqdn+=("$fqdn")
  plan_algo+=("$algo")
  plan_kind+=("$kind")
  plan_ip+=("$ip")
  plan_www+=("$www")
  plan_expires+=("${enddate#notAfter=}")
}

# Function to select the certificates to renew
select_targets() {
  local file name

  if [[ "$renew_all" = false ]]; then
    case "$target_fqdn" in
    trusted_id | root_ca | ca)
      print_error "'$target_fqdn' is a CA certificate. This script does not renew CA certificates."
      exit 2
      ;;
    esac
    is_valid_fqdn "$target_fqdn" || {
      print_error "'$target_fqdn' is not a valid FQDN."
      exit 2
    }
    plan_certificate "$target_fqdn" || exit 2
    return
  fi

  for file in "$certs_certificates_dir"/*.pem; do
    [[ -f "$file" ]] || continue
    name=$(basename "$file" .pem)
    case "$name" in
    *_chain_bundle | *_haproxy | *_bundle) continue ;;
    esac
    if openssl x509 -in "$file" -noout -checkend "$((within_days * 86400))" >/dev/null 2>&1; then
      continue
    fi
    # A revoked certificate is not renewed
    if is_revoked "$file"; then
      continue
    fi
    plan_certificate "$name" || plan_failed=$((plan_failed + 1))
  done
}

# Function to print the plan
print_plan() {
  local i
  print_cyan "=== Renewal plan ==="
  printf '%-40s %-6s %-7s %-26s %s\n' "FQDN" "ALGO" "ROLE" "EXPIRES" "KEY"
  for i in "${!plan_fqdn[@]}"; do
    printf '%-40s %-6s %-7s %-26s %s\n' "${plan_fqdn[$i]}" "${plan_algo[$i]}" "${plan_kind[$i]}" "${plan_expires[$i]}" \
      "$([[ "$reuse_key" = true ]] && echo "reuse" || echo "new")"
  done
  echo
  echo "Old files are archived in $archive_root/<fqdn>/<date> first. Nothing is deleted."
}

# Function to normalize a serial number (uppercase, without leading zeros)
normalize_serial() {
  local value="${1#serial=}"
  printf '%s' "$value" | tr 'a-f' 'A-F' | sed 's/^0*//'
}

# Function to list the serial numbers of the valid (V) entries of an FQDN
list_valid_serials() {
  awk -F'\t' -v cn="/CN=$1" '
    $1 == "V" && (substr($NF, length($NF) - length(cn) + 1) == cn || index($NF, cn "/")) { print $4 }' \
    "$db_dir/index.txt"
}

# Function to mark all valid entries of an FQDN, except one, as superseded
supersede_entries() {
  local fqdn="$1" keep status=0 serial
  keep=$(normalize_serial "$2")
  while IFS= read -r serial; do
    [[ -n "$serial" ]] || continue
    [[ "$(normalize_serial "$serial")" != "$keep" ]] || continue
    if ! openssl ca -config "$base_dir/openssl.cnf/cert.cnf" ${ca_options[@]+"${ca_options[@]}"} \
      -revoke "$base_dir/newcerts/$serial.pem" -crl_reason superseded >>"$log" 2>&1; then
      print_error "Cannot mark database entry $serial of $fqdn as superseded."
      status=1
    fi
  done < <(list_valid_serials "$fqdn")
  return $status
}

# Function to set unique_subject to no for the renewals
disable_unique_subject() {
  if [[ -f "$attr_file" ]]; then
    attr_original=$(cat "$attr_file")
  else
    attr_created=true
  fi
  attr_changed=true
  echo "unique_subject = no" >"$attr_file"
}

# Function to restore index.txt.attr to its original content
restore_unique_subject() {
  [[ "$attr_changed" = true ]] || return 0
  if ! database_is_unique "$db_dir/index.txt"; then
    print_warning "index.txt has valid entries with the same name. unique_subject stays 'no' in $attr_file. Revoke or remove the extra entries and set it back to 'yes'."
    attr_changed=false
    return 0
  fi
  if [[ "$attr_created" = true ]]; then
    rm -f "$attr_file"
  else
    printf '%s\n' "$attr_original" >"$attr_file"
  fi
  attr_changed=false
}

# Function to archive the files of a certificate
archive_certificate() {
  local fqdn="$1" stamp dir n=0 rel
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  (umask 077 && mkdir -p "$archive_root/$fqdn") || return 1
  dir="$archive_root/$fqdn/$stamp"
  until (umask 077 && mkdir "$dir") 2>/dev/null; do
    n=$((n + 1))
    [[ "$n" -lt 100 ]] || return 1
    dir="$archive_root/$fqdn/$stamp-$n"
  done
  archive_dir="$dir"

  for rel in \
    "certs/certificates/$fqdn.pem" \
    "certs/certificates/$fqdn.crt" \
    "certs/certificates/${fqdn}_chain_bundle.pem" \
    "certs/certificates/${fqdn}_chain_bundle.crt" \
    "certs/certificates/${fqdn}_haproxy.pem" \
    "private/certificates/$fqdn.pem" \
    "private/certificates/$fqdn.key" \
    "csr/$fqdn.pem" \
    "extfiles/$fqdn.cnf"; do
    [[ -f "$base_dir/$rel" ]] || continue
    (umask 077 && mkdir -p "$archive_dir/$(dirname "$rel")" && cp -p "$base_dir/$rel" "$archive_dir/$rel") || return 1
  done
}

# Function to restore the archived files of a certificate
restore_archive() {
  local rel
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    cp -p "$archive_dir/$rel" "$base_dir/$rel" || return 1
  done < <(cd "$archive_dir" && find . -type f ! -name renew.log -print0)
}

# Function to check a renewed certificate
check_renewal() {
  local fqdn="$1" old_serial="$2" old_san="$3"
  local cert="$certs_certificates_dir/$fqdn.pem"
  local chain="$certs_certificates_dir/${fqdn}_chain_bundle.pem"
  local haproxy="$certs_certificates_dir/${fqdn}_haproxy.pem"
  local key="$private_certificates_dir/$fqdn.pem"

  openssl verify -CAfile "$certs_intermediate_dir/ca_chain_bundle.pem" "$cert" >>"$log" 2>&1 || {
    print_error "The new certificate does not verify against the CA chain."
    return 1
  }
  openssl verify -CAfile "$certs_intermediate_dir/ca_chain_bundle.pem" "$chain" >>"$log" 2>&1 || {
    print_error "The new chain bundle does not verify."
    return 1
  }
  openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1 || {
    print_error "The new certificate has already expired."
    return 1
  }
  [[ "$(openssl x509 -in "$cert" -noout -serial)" != "$old_serial" ]] || {
    print_error "The certificate was not replaced (same serial number)."
    return 1
  }
  [[ "$(openssl x509 -in "$cert" -noout -pubkey 2>/dev/null)" = "$(openssl pkey -in "$key" -pubout 2>/dev/null)" ]] || {
    print_error "The new certificate does not match the private key."
    return 1
  }
  [[ "$(get_san "$cert")" = "$old_san" ]] || {
    print_error "The names of the new certificate differ from the old certificate."
    return 1
  }
  if [[ -f "$haproxy" ]]; then
    [[ "$(stat -c %a "$haproxy")" = "600" ]] || {
      print_error "The HAProxy bundle does not have mode 600."
      return 1
    }
    openssl verify -CAfile "$certs_intermediate_dir/ca_chain_bundle.pem" "$haproxy" >>"$log" 2>&1 || {
      print_error "The HAProxy bundle does not verify."
      return 1
    }
  fi
  if ! openssl x509 -in "$certs_intermediate_dir/ca.pem" -noout -checkend "$((366 * 86400))" >/dev/null 2>&1; then
    print_warning "The intermediate CA expires within the validity of the new certificate of $fqdn."
  fi
}

# Function to run the hooks after a successful renewal
run_hooks() {
  local fqdn="$1" hook status=0
  local haproxy="$certs_certificates_dir/${fqdn}_haproxy.pem"
  [[ -f "$haproxy" ]] || haproxy=""
  [[ -d "$hooks_dir" ]] || return 0
  for hook in "$hooks_dir"/*; do
    [[ -f "$hook" ]] && [[ -x "$hook" ]] || continue
    if ! "$hook" "$fqdn" "$certs_certificates_dir/$fqdn.pem" "$certs_certificates_dir/${fqdn}_chain_bundle.pem" \
      "$private_certificates_dir/$fqdn.key" "$haproxy" >>"$log" 2>&1 9>&-; then
      print_error "Hook failed: $hook (see $log)"
      status=1
    fi
  done
  return $status
}

# Function to renew one certificate
renew_certificate() {
  local i="$1" fqdn="${plan_fqdn[$1]}" old_serial old_san script args=()

  echo
  print_cyan "=== Renew $fqdn ==="

  archive_certificate "$fqdn" || {
    print_error "Cannot archive the files of $fqdn. Nothing was changed."
    return 1
  }
  log="$archive_dir/renew.log"
  echo "Archive: $archive_dir"

  old_serial=$(openssl x509 -in "$certs_certificates_dir/$fqdn.pem" -noout -serial)
  old_san=$(get_san "$certs_certificates_dir/$fqdn.pem")
  renewal_old_serial="$old_serial"
  renewal_in_progress="$fqdn"

  # Select the certificate script. The names come from the old certificate.
  if [[ "$fqdn" = "localhost" ]]; then
    script="$certificate_script_dir/cert_ecdsa_localhost.sh"
    args=(--non-interactive)
  else
    script="$certificate_script_dir/cert_${plan_algo[$i]}_${plan_kind[$i]}.sh"
    args=(--fqdn "$fqdn")
    [[ -z "${plan_ip[$i]}" ]] || args+=(--ip "${plan_ip[$i]}")
    # Only a client certificate needs --www; a server certificate always has it
    if [[ "${plan_kind[$i]}" = "client" ]] && [[ "${plan_www[$i]}" = true ]]; then
      args+=(--www)
    fi
  fi
  [[ "$reuse_key" = false ]] || args+=(--reuse-key)

  if TLS_LOCK_HELD=1 bash "$script" "${args[@]}" </dev/null >"$log" 2>&1 && check_renewal "$fqdn" "$old_serial" "$old_san"; then
    # From here the new certificate is in use, so an interrupt must not restore
    # the old files.
    renewal_in_progress=""
    # The old entry is superseded by the new certificate
    supersede_entries "$fqdn" "$(openssl x509 -in "$certs_certificates_dir/$fqdn.pem" -noout -serial)" || failed=$((failed + 1))
    echo "Renewed: $(openssl x509 -in "$certs_certificates_dir/$fqdn.pem" -noout -enddate)"
    run_hooks "$fqdn" || failed=$((failed + 1))
    renewed=$((renewed + 1))
    return 0
  fi

  print_error "Renewal of $fqdn failed. Last lines of $log:"
  tail -n 10 "$log" >&2
  if restore_archive; then
    echo "The old files of $fqdn were restored from $archive_dir." >&2
  else
    print_error "Restoring failed. Copy the files from $archive_dir back by hand."
  fi
  # A certificate that was issued but rolled back must not stay valid in the database
  supersede_entries "$fqdn" "$old_serial" || true
  renewal_in_progress=""
  return 1
}

# Function to restore the old files when the script is interrupted during a
# renewal. It runs from the INT and TERM traps.
# shellcheck disable=SC2329
on_interrupt() {
  if [[ -n "$renewal_in_progress" ]]; then
    print_warning "Interrupted during the renewal of $renewal_in_progress."
    if restore_archive; then
      echo "The old files of $renewal_in_progress were restored from $archive_dir." >&2
    else
      print_error "Restoring failed. Copy the files from $archive_dir back by hand."
    fi
    supersede_entries "$renewal_in_progress" "$renewal_old_serial" || true
  fi
  exit 1
}

# Main process
parse_arguments "$@"
preflight
# Prevent two renewals at the same time. The lock is taken before the plan is
# made, so the plan matches the database. The certificate scripts that this
# script starts skip the lock (TLS_LOCK_HELD=1), and the hooks do not inherit
# it (9>&-), so a hook cannot keep it.
[[ "$dry_run" = true ]] || acquire_lock 2 0 "Another renewal or certificate script is running."
select_targets
warn_ca_certificates

if [[ "${#plan_fqdn[@]}" -eq 0 ]]; then
  if [[ "$plan_failed" -gt 0 ]]; then
    exit 1
  fi
  echo "Nothing to renew."
  exit 0
fi

print_plan

if [[ "$dry_run" = true ]]; then
  [[ "$plan_failed" -eq 0 ]] || exit 1
  exit 0
fi

if [[ "$assume_yes" = false ]] && ! confirm; then
  echo "Cancelled. Nothing was changed."
  exit 0
fi

trap restore_unique_subject EXIT
trap on_interrupt INT TERM
disable_unique_subject

for i in "${!plan_fqdn[@]}"; do
  if ! renew_certificate "$i"; then
    failed=$((failed + 1))
  fi
done

restore_unique_subject

echo
print_cyan "Renewed: $renewed. Failed: $((failed + plan_failed))."
if [[ "$((failed + plan_failed))" -gt 0 ]]; then
  exit 1
fi
exit 0
