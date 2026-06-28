#!/usr/bin/env bash

# ============================================
# Recon Framework - Dependency Checker
# ============================================

# Get the directory where this script is located
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load required libraries
source "$BASE_DIR/config.sh"
source "$BASE_DIR/lib/logger.sh"
source "$BASE_DIR/lib/helpers.sh"

# List of required tools
REQUIRED_TOOLS=(
    nmap
    subfinder
    httpx
    dnsx
    naabu
    nuclei
    katana
    assetfinder
    amass
)

check_dependencies() {

    separator
    log_info "Checking required tools..."
    separator

    local missing=0

    for tool in "${REQUIRED_TOOLS[@]}"; do

        if command_exists "$tool"; then
            log_success "$tool is installed"
        else
            log_error "$tool is NOT installed"
            ((missing++))
        fi

    done

    separator

    if [[ $missing -eq 0 ]]; then
        log_success "All dependencies are installed."
    else
        log_warn "$missing tool(s) are missing."
    fi

    separator
}

check_dependencies
