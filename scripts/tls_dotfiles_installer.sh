#!/bin/bash

# Script Name: tls_dotfiles_installer.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 3.0.0

# Description:
# This script adds the aliases of this repository to ~/.bashrc. It avoids
# duplication by checking for existing entries and only appends the content if
# it's missing. The script does not remove or change any other file.

# Usage: ./tls_dotfiles_installer.sh [-h|--help]
#
# Options:
#  -h, --help  Show this help.
#
# Without options the script appends the aliases to ~/.bashrc.

# Notes:
# - Ensure the content to be added is properly formatted to avoid conflicts
#   with existing aliases.
# - The script assumes the user has a specific directory structure with
#   the file ~/openssl/dotfiles/.bash_aliases for aliases.

# Stop script on error
set -Eeuo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    sed -n '/^# Usage:/,/^$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Error: Unknown option: $1" >&2
    exit 2
    ;;
  esac
done

# Define the paths to the files
bashrc_path="$HOME/.bashrc"
aliases_path="$HOME/openssl/dotfiles/.bash_aliases"

# Check if .bashrc exists and is writable
if [[ ! -w "$bashrc_path" ]]; then
  echo "Error: $bashrc_path is not writable. Please check your permissions." >&2
  exit 1
fi

# Add the necessary configuration to .bashrc if it's not already present. The
# first pattern is the line that older versions of this script wrote.
if grep -qF -e "if [ -f $aliases_path ]; then" -e "if [ -f \"$aliases_path\" ]; then" "$bashrc_path"; then
  echo "Configuration already exists in $bashrc_path"
else
  {
    echo "# Alias definitions for openssl."
    echo "# You may want to put all your additions into a separate file like"
    echo "# ~/openssl/dotfiles/.bash_aliases, instead of adding them here directly."
    echo ""
    echo "if [ -f \"$aliases_path\" ]; then"
    echo "  . \"$aliases_path\""
    echo "fi"
    echo ""
  } >>"$bashrc_path"
  echo "Configuration added to $bashrc_path"
fi

# Inform the user about the completion of the script
echo "Installation completed. Open a new shell to use the aliases."

exit 0
