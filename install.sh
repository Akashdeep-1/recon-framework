#!/usr/bin/env bash

# ============================================
# Recon Framework - Dependency Manager
# ============================================

set -Eeuo pipefail

# Get the directory where this script is located
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load required libraries
# shellcheck source=./config.sh
source "$BASE_DIR/config.sh"
# shellcheck source=./lib/logger.sh
source "$BASE_DIR/lib/logger.sh"
# shellcheck source=./lib/helpers.sh
source "$BASE_DIR/lib/helpers.sh"

# Required reconnaissance tools actually invoked by the pipeline
REQUIRED_TOOLS=(
    subfinder
    assetfinder
    dnsx
    naabu
    httpx
    katana
    nuclei
)

# Optional system tools
OPTIONAL_TOOLS=(
    jq
)

declare -A TOOL_INSTALL_CMDS=(
    ["subfinder"]="go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    ["assetfinder"]="go install -v github.com/tomnomnom/assetfinder@latest"
    ["dnsx"]="go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    ["naabu"]="go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    ["httpx"]="go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest"
    ["katana"]="go install -v github.com/projectdiscovery/katana/cmd/katana@latest"
    ["nuclei"]="go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
)

usage() {
    cat << EOF
Recon Framework Dependency Manager

Usage:
  ./install.sh [mode]

Modes:
  --check                 Check installed dependencies (default)
  --install               Attempt automated Go-based installation for missing tools
  --install-instructions  Show installation commands for missing tools
  -h, --help              Show this help message

Exit Codes:
  0                       All required dependencies are installed
  1                       One or more required dependencies are missing or install failed
EOF
}

check_dependencies() {
    separator
    log_info "Verifying required reconnaissance tools..."
    separator

    local missing_required=0
    local missing_optional=0

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command_exists "$tool"; then
            log_success "$tool is installed"
        else
            log_error "$tool is NOT installed [REQUIRED]"
            missing_required=$(( missing_required + 1 ))
        fi
    done

    separator
    log_info "Verifying optional helper tools..."
    separator

    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if command_exists "$tool"; then
            log_success "$tool is installed [OPTIONAL]"
        else
            log_warn "$tool is NOT installed [OPTIONAL]"
            missing_optional=$(( missing_optional + 1 ))
        fi
    done

    separator

    if (( missing_required == 0 )); then
        log_success "All required dependencies are installed."
        if (( missing_optional > 0 )); then
            log_info "$missing_optional optional tool(s) missing (non-critical)."
        fi
        return 0
    else
        log_error "$missing_required required tool(s) are missing."
        log_info "Run './install.sh --install-instructions' for setup commands."
        return 1
    fi
}

show_instructions() {
    log_info "To install required tools using Go (requires Go 1.21+):"
    echo ""
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command_exists "$tool"; then
            echo "  # Install $tool:"
            echo "  ${TOOL_INSTALL_CMDS[$tool]}"
            echo ""
        fi
    done
    echo "Ensure \$GOPATH/bin or \$HOME/go/bin is in your system \$PATH."
}

install_missing() {
    if ! command_exists go; then
        log_error "Go is not installed or not in PATH. Cannot perform automated installation."
        show_instructions
        return 1
    fi

    log_info "Attempting automated installation of missing tools..."
    local failed=0

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command_exists "$tool"; then
            log_info "Installing $tool..."
            local cmd="${TOOL_INSTALL_CMDS[$tool]}"
            if eval "$cmd"; then
                log_success "Successfully installed $tool"
            else
                log_error "Failed to install $tool"
                failed=$(( failed + 1 ))
            fi
        fi
    done

    if (( failed == 0 )); then
        log_success "All missing tools installed successfully."
        return 0
    else
        log_error "$failed tool(s) failed to install."
        return 1
    fi
}

MODE="${1:---check}"

case "$MODE" in
    --check)
        check_dependencies
        exit $?
        ;;
    --install)
        install_missing
        exit $?
        ;;
    --install-instructions)
        show_instructions
        exit 0
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        log_error "Unknown option: $MODE"
        usage
        exit 1
        ;;
esac
