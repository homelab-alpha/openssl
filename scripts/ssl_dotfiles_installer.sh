#!/bin/bash

# Script Name: ssl_dotfiles_installer.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-18T17:31:25+01:00
# Version: 2.5.0

# Description:
# This script updates ~/.bashrc by adding necessary content if not already
# present. It avoids duplication by checking for existing entries and only
# appends the content if it's missing.

# Usage:
# No options or arguments required.
# Run the script to append content to ~/.bashrc and remove specific files
# in the OpenSSL directory.

# Notes:
# - Ensure the content to be added is properly formatted to avoid conflicts
#   with existing aliases.
# - The script assumes the user has a specific directory structure with
#   the file ~/openssl/dotfiles/.bash_aliases for aliases.

# Main Program:

# Define the paths to the files
BASHRC_PATH="$HOME/.bashrc"
ALIASES_PATH="$HOME/openssl/dotfiles/.bash_aliases"

# Check if .bashrc exists and is writable
if [ ! -w "$BASHRC_PATH" ]; then
    echo "Error: $BASHRC_PATH is not writable. Please check your permissions."
    exit 1
fi

# Add the necessary configuration to .bashrc if it's not already present
if ! grep -qF "if [ -f $ALIASES_PATH ]; then" "$BASHRC_PATH"; then
    {
        echo "# Alias definitions for openssl."
        echo "# You may want to put all your additions into a separate file like"
        echo "# ~/openssl/dotfiles/.bash_aliases, instead of adding them here directly."
        echo ""
        echo "if [ -f $ALIASES_PATH ]; then"
        echo "    . $ALIASES_PATH"
        echo "fi"
        echo ""
    } >>"$BASHRC_PATH"
    echo "Configuration added to $BASHRC_PATH"
else
    echo "Configuration already exists in $BASHRC_PATH"
fi

# Remove specific files in the OpenSSL directory using an array
files_to_remove=(
    "$HOME/openssl/.git"
    "$HOME/openssl/.github"
    "$HOME/openssl/.gitignore"
    "$HOME/openssl/.gitleaksignore"
    "$HOME/openssl/CODE_OF_CONDUCT.md"
    "$HOME/openssl/CODE_STYLE_AND_STANDARDS_GUIDES.md"
    "$HOME/openssl/CONTRIBUTING.md"
)

# Remove the files and check if they exist
for file in "${files_to_remove[@]}"; do
    if [ -e "$file" ]; then
        rm -rf "$file"
        echo "Removed: $file"
    else
        echo "File not found: $file"
    fi
done

# Inform the user about the completion of the script
echo "Installation completed. .bashrc has been updated, and the specified files have been removed."

# Optionally, restart the shell (optional line to consider uncommenting if needed)
# exec bash

exit 0
