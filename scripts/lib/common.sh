#!/bin/bash

# Script Name: common.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 1.0.0

# Description:
# Shared functions for the scripts in this repository. This file is not a
# program: the other scripts load it with "source". It holds the functions that
# every script needs, such as the messages, the base directory with the
# fallback to the old name ~/ssl, the check of an FQDN, and the passphrase and
# archive functions of the certificate authority scripts.

# Usage: source "<path to scripts>/lib/common.sh"

# Notes:
# - The file sets no shell options and runs no command when it is loaded.
# - The certificates are for a homelab and for testing.

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

# Function to print section headers
print_section_header() {
  echo
  print_cyan "=== $1 ==="
}

# Function to show the usage of the calling script. It prints the header lines
# from "# Usage:" up to the first line that matches the pattern in $1 (the
# default is the first empty line). That last line is not printed.
show_usage() {
  local until="${1:-^\$}"
  sed -n "/^# Usage:/,/${until}/p" "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

# Function to stop when OpenSSL is not installed
require_openssl() {
  if ! command -v openssl >/dev/null 2>&1; then
    print_error "OpenSSL is not installed. Install it before you run this script."
    exit "${1:-1}"
  fi
}

# Function to set base_dir. The old name ~/ssl is used while ~/tls does not
# exist.
set_base_dir() {
  base_dir="$HOME/tls"
  if [[ ! -e "$base_dir" && -d "$HOME/ssl" ]]; then
    base_dir="$HOME/ssl"
    echo "Warning: using the old directory $HOME/ssl. Run tls_directory_migrate.sh to move it to $HOME/tls." >&2
  fi
}

# Function to change to $HOME. Configuration files that were copied to
# ~/tls/openssl.cnf before version 0.2.0 contain "HOME = .", so their paths
# depend on the current directory. The current files use $ENV::HOME and do not
# need this.
enter_home() {
  cd "$HOME" || {
    print_error "Cannot change to $HOME."
    exit "${1:-1}"
  }
}

# Function to check that a value is a usable FQDN: labels of letters, digits,
# and hyphens, separated by dots, with an optional wildcard label at the start
# (*.example.test). The Common Name has a maximum of 64 characters.
is_valid_fqdn() {
  local label='[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?'
  [[ -n "$1" && "${#1}" -le 64 && "$1" =~ ^(\*\.)?${label}(\.${label})*$ ]]
}

# Function to check if unique_subject is "yes" in index.txt.attr
unique_subject_enabled() {
  grep -Eq '^unique_subject[[:space:]]*=[[:space:]]*yes' "$1" 2>/dev/null
}

# Function to ask for confirmation. Only the answer "yes" continues.
confirm() {
  local answer
  read -r -p "Do you want to continue? (yes/no): " answer
  [[ "$answer" == "yes" ]]
}

# Function to check if a private key file is encrypted with a passphrase
key_is_encrypted() {
  grep -q 'ENCRYPTED' "$1" 2>/dev/null
}

# Function to get a passphrase. The result is stored in the variable named by
# $1. The environment variable named by $2 is used when it is set, so the
# scripts can run without questions. Otherwise the passphrase is asked for,
# and asked a second time when $4 is "new".
get_passphrase() {
  local target="$1" env_name="$2" label="$3" mode="${4:-existing}" first second
  if [[ -n "${!env_name:-}" ]]; then
    printf -v "$target" '%s' "${!env_name}"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    print_error "The passphrase of the $label is needed. Set $env_name, or run the script in a terminal."
    return 1
  fi
  read -r -s -p "Enter the passphrase of the $label: " first
  echo >&2
  if [[ "$mode" == "new" ]]; then
    if [[ "${#first}" -lt 8 ]]; then
      print_error "Use a passphrase of 8 characters or more."
      return 1
    fi
    read -r -s -p "Enter the passphrase again: " second
    echo >&2
    if [[ "$first" != "$second" ]]; then
      print_error "The passphrases are not the same."
      return 1
    fi
  fi
  printf -v "$target" '%s' "$first"
}

# Function to copy existing files to a dated folder under
# $base_dir/archive/<label>/ before they are replaced. Files that do not exist
# are skipped. Nothing is created when no file exists.
archive_files() {
  local label="$1" stamp dir n=0 file found=false
  shift
  for file in "$@"; do
    [[ -f "$file" ]] && found=true
  done
  [[ "$found" == "true" ]] || return 0

  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  (umask 077 && mkdir -p "$base_dir/archive/$label") || return 1
  dir="$base_dir/archive/$label/$stamp"
  until (umask 077 && mkdir "$dir") 2>/dev/null; do
    n=$((n + 1))
    [[ "$n" -lt 100 ]] || return 1
    dir="$base_dir/archive/$label/$stamp-$n"
  done
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    (umask 077 && mkdir -p "$dir/$(dirname "${file#"$base_dir"/}")" &&
      cp -p "$file" "$dir/${file#"$base_dir"/}") || return 1
  done
  echo "Archive: $dir"
}
