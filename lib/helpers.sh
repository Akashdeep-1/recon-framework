#!/usr/bin/env bash

# ============================================
# Recon Framework - Helper Functions
# ============================================

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create a directory if it doesn't exist
create_directory() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

# Check if a file exists
file_exists() {
    [[ -f "$1" ]]
}

# Check if a directory exists
directory_exists() {
    [[ -d "$1" ]]
}

# Get current timestamp
timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Print a horizontal line
separator() {
    printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'
}

# Exit with an error message
die() {
    log_error "$1"
    exit 1
}
