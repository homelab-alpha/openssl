#!/bin/bash

# Script Name: Add content to .bashrc
# Author: GJS (homelab-aplha)
# Date: 2024-03-23T06:39:01Z
# Version: 1.0

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
fi

echo "Installation completed. .bashrc has been updated and the shell has been restarted."

exit
