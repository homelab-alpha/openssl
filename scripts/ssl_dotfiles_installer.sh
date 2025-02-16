#!/bin/bash

# Script Name: ssl_dotfiles_installer.sh
# Author: GJS (homelab-alpha)
# Date: 2025-02-16T07:24:43+01:00
# Version: 2.0.0

# Description:
# This script adds specified content to the ~/.bashrc file, avoiding duplication.
# It checks if ~/.bashrc exists and appends the content to the end if it doesn't already exist.

# Usage:
# Options and arguments:
# - No options or arguments required.
# - Run the script to add specified content to ~/.bashrc.

# Notes:
# - Ensure that the content to be added is properly formatted and won't cause conflicts with existing aliases.
# - This script assumes that the user has a specific directory structure and file (~/openssl/dotfiles/.bash_aliases) for aliases.

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
