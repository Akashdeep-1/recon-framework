#!/usr/bin/env bash

# ============================================
# Recon Framework - Logger Library
# ============================================

# Load configuration if it hasn't been loaded yet.
# This provides the color variables (RED, GREEN, etc.).
if [[ -z "${RESET:-}" ]]; then
    source "$(dirname "$0")/../config.sh"
fi

# Print an informational message.
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${RESET} ${message}"
}

# Print a success message.
log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${RESET} ${message}"
}

# Print a warning message.
log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${RESET} ${message}"
}

# Print an error message.
log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${RESET} ${message}"
}

# Print a debug message.
log_debug() {
    local message="$1"
    echo -e "${CYAN}[DEBUG]${RESET} ${message}"
}
